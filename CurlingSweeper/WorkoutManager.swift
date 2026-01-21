//
//  WorkoutManager.swift
//  CurlingSweeper
//
//  Created by JEREMY KARN on 2025-12-21.
//

import Foundation
import HealthKit
import Observation
import CoreMotion

@Observable
@MainActor
final class WorkoutManager {

    // MARK: - Observable Properties

    var isWorkoutActive = false
    var isPaused = false
    var heartRate: Double = 0
    var averageHeartRate: Double = 0
    var activeCalories: Double = 0
    var elapsedTime: TimeInterval = 0

    // Heart rate averaging
    private var heartRateSum: Double = 0
    private var heartRateCount: Int = 0

    // Shot tracking
    var isShotActive = false

    // End tracking
    var currentEnd: Int = 0

    // Brush stroke counting
    var strokeCountEnd: Int = 0      // Strokes in current end
    var strokeCountTotal: Int = 0    // Total strokes in workout

    // Debug mode for accelerometer recording
    var isDebugMode = false
    var debugSampleCount: Int = 0
    var currentShotInEnd: Int = 0    // Shot number within current end (1-based)
    private var debugData: [(timestamp: TimeInterval, x: Double, y: Double, z: Double, strokes: Int)] = []
    private var shotStartTime: Date?

    // Callback for syncing status to phone
    var onStatusUpdate: ((Bool, TimeInterval, Double, Double, Int, Int) -> Void)?
    private var lastSyncTime: Date?

    // Callback for sending debug data to phone
    var onSendDebugData: ((String, String) -> Void)?

    // MARK: - Private Properties

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startDate: Date?

    // Motion detection - Garmin algorithm
    private let motionManager = CMMotionManager()

    // Sweep detection thresholds (using userAcceleration with gravity removed)
    private let sweepThresholdY: Double = 0.5  // Minimum Y amplitude to count as valid sweep motion
    private var lastYSign: Int = 0             // -1 for negative, 0 for neutral, 1 for positive
    private var peakYInPhase: Double = 0       // Track peak |Y| in current phase
    private var lastStrokeTime: Date?          // Time of last stroke for debouncing
    private let minStrokeInterval: TimeInterval = 0.08  // Minimum 80ms between strokes
    private var timer: Timer?
    private var delegateHandler: WorkoutDelegateHandler?

    // MARK: - Initialization

    init() {}

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            return false
        }

        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType()
        ]

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.workoutType()
        ]

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            return true
        } catch {
            print("HealthKit authorization failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Workout Session Control

    func startWorkout() async {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .indoor

        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            builder = session?.associatedWorkoutBuilder()

            // Create delegate handler
            delegateHandler = WorkoutDelegateHandler(manager: self)
            session?.delegate = delegateHandler
            builder?.delegate = delegateHandler

            builder?.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            let start = Date()
            session?.startActivity(with: start)
            try await builder?.beginCollection(at: start)

            startDate = start
            isWorkoutActive = true
            isPaused = false
            currentEnd = 1
            startTimer()
            startMotionUpdates()
            clearDebugData()  // Fresh debug data for new workout

        } catch {
            print("Failed to start workout: \(error.localizedDescription)")
        }
    }

    func pauseWorkout() {
        session?.pause()
        isPaused = true
        stopTimer()
    }

    func resumeWorkout() {
        session?.resume()
        isPaused = false
        startTimer()
    }

    func endWorkout() async {
        sendAndClearDebugData()  // Auto-upload any remaining debug data
        session?.end()
        stopTimer()

        do {
            try await builder?.endCollection(at: Date())
            try await builder?.finishWorkout()
        } catch {
            print("Failed to end workout: \(error.localizedDescription)")
        }

        resetState()
    }

    func discardWorkout() async {
        session?.end()
        stopTimer()

        builder?.discardWorkout()

        resetState()
    }

    private func resetState() {
        isWorkoutActive = false
        isPaused = false
        heartRate = 0
        averageHeartRate = 0
        heartRateSum = 0
        heartRateCount = 0
        activeCalories = 0
        elapsedTime = 0
        currentEnd = 0
        currentShotInEnd = 0
        isShotActive = false
        stopMotionUpdates()
        resetStrokeCount()
        session = nil
        builder = nil
        startDate = nil
        delegateHandler = nil

        // Sync final status to phone
        onStatusUpdate?(false, 0, 0, 0, 0, 0)
    }

    // MARK: - End Tracking

    func markNewEnd() {
        sendAndClearDebugData()  // Auto-upload any remaining debug data
        currentEnd += 1
        currentShotInEnd = 0  // Reset shot counter for new end
        isShotActive = false
        strokeCountEnd = 0  // Reset per-end stroke count
    }

    // MARK: - Brush Stroke Detection

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            print("Device motion not available")
            return
        }

        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0  // 60Hz for better stroke detection
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }
            Task { @MainActor in
                self.processMotionData(motion)
            }
        }
    }

    private func stopMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
        resetSweepDetection()
    }

    private func resetSweepDetection() {
        lastYSign = 0
        peakYInPhase = 0
        lastStrokeTime = nil
    }

    private func processMotionData(_ motion: CMDeviceMotion) {
        // Use userAcceleration which has gravity removed
        let xAccel = motion.userAcceleration.x
        let yAccel = motion.userAcceleration.y
        let zAccel = motion.userAcceleration.z

        // Only process when shot is active
        guard isShotActive, let startTime = shotStartTime else { return }

        // Detect sweep motion
        detectSweep(yAccel)

        // Record debug data if enabled
        if isDebugMode {
            let timestamp = Date().timeIntervalSince(startTime)
            debugData.append((timestamp: timestamp, x: xAccel, y: yAccel, z: zAccel, strokes: strokeCountEnd))
            debugSampleCount = debugData.count
        }
    }

    /// Stroke detection based on Y-axis zero-crossings with amplitude threshold
    /// Counts a stroke when Y changes sign and the previous phase exceeded the amplitude threshold
    private func detectSweep(_ yAccel: Double) {
        // Determine current sign: -1 for negative, 1 for positive, 0 for near-zero
        let currentSign: Int
        if yAccel > 0.05 {
            currentSign = 1
        } else if yAccel < -0.05 {
            currentSign = -1
        } else {
            currentSign = 0
        }

        // Track peak amplitude in current phase
        if abs(yAccel) > peakYInPhase {
            peakYInPhase = abs(yAccel)
        }

        // Detect sign change (zero crossing)
        if currentSign != 0 && lastYSign != 0 && currentSign != lastYSign {
            // Sign changed - check if previous phase had enough amplitude
            if peakYInPhase >= sweepThresholdY {
                // Check debounce
                let now = Date()
                if lastStrokeTime == nil || now.timeIntervalSince(lastStrokeTime!) >= minStrokeInterval {
                    countStroke()
                    lastStrokeTime = now
                }
            }
            // Reset peak for new phase
            peakYInPhase = abs(yAccel)
        }

        // Update last sign (only if not neutral)
        if currentSign != 0 {
            lastYSign = currentSign
        }
    }

    private func countStroke() {
        strokeCountEnd += 1
        strokeCountTotal += 1
    }

    private func resetStrokeCount() {
        strokeCountEnd = 0
        strokeCountTotal = 0
        resetSweepDetection()
    }

    // MARK: - Debug Data

    /// Sends debug data to phone if available, then clears it
    private func sendAndClearDebugData() {
        guard isDebugMode && hasDebugData else { return }
        let csv = getDebugCSV()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let dateStr = formatter.string(from: Date())
        let fileName = "workout_\(dateStr)_end-\(currentEnd)_shot-\(currentShotInEnd).csv"
        onSendDebugData?(csv, fileName)
        clearDebugData()
    }

    /// Returns debug data as CSV string
    func getDebugCSV() -> String {
        var csv = "timestamp,x,y,z,strokes\n"
        for sample in debugData {
            csv += String(format: "%.4f,%.6f,%.6f,%.6f,%d\n",
                          sample.timestamp, sample.x, sample.y, sample.z, sample.strokes)
        }
        return csv
    }

    /// Clears all recorded debug data
    func clearDebugData() {
        debugData.removeAll()
        debugSampleCount = 0
        shotStartTime = nil
    }

    /// Returns true if there is debug data to send
    var hasDebugData: Bool {
        !debugData.isEmpty
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsedTime()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateElapsedTime() {
        guard let startDate = startDate else { return }
        elapsedTime = Date().timeIntervalSince(startDate)

        // Sync status to phone every second
        if lastSyncTime == nil || Date().timeIntervalSince(lastSyncTime!) >= 1.0 {
            lastSyncTime = Date()
            onStatusUpdate?(isWorkoutActive, elapsedTime, activeCalories, heartRate, strokeCountTotal, currentEnd)
        }
    }

    // MARK: - Shot Tracking

    func startShot() {
        currentShotInEnd += 1
        isShotActive = true
        shotStartTime = Date()
        resetSweepDetection()
    }

    func endShot() {
        isShotActive = false
        sendAndClearDebugData()  // Auto-upload debug data after each shot
        shotStartTime = nil
    }

    // MARK: - Formatting Helpers

    func formattedElapsedTime() -> String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        let tenths = Int((elapsedTime.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }

    // MARK: - Delegate Callbacks

    fileprivate func handleSessionStateChange(to state: HKWorkoutSessionState) {
        switch state {
        case .running:
            isWorkoutActive = true
            isPaused = false
        case .paused:
            isPaused = true
        case .ended:
            isWorkoutActive = false
            isPaused = false
        default:
            break
        }
    }

    fileprivate func handleHeartRateUpdate(_ value: Double) {
        heartRate = value

        // Update average
        heartRateSum += value
        heartRateCount += 1
        averageHeartRate = heartRateSum / Double(heartRateCount)
    }

    fileprivate func handleCaloriesUpdate(_ value: Double) {
        activeCalories = value
    }
}

// MARK: - Delegate Handler

private class WorkoutDelegateHandler: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    private weak var manager: WorkoutManager?

    init(manager: WorkoutManager) {
        self.manager = manager
        super.init()
    }

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState,
                        date: Date) {
        Task { @MainActor in
            manager?.handleSessionStateChange(to: toState)
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didFailWithError error: Error) {
        print("Workout session failed: \(error.localizedDescription)")
    }

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }

            let statistics = workoutBuilder.statistics(for: quantityType)

            // Heart rate
            if quantityType == HKQuantityType.quantityType(forIdentifier: .heartRate) {
                let heartRateUnit = HKUnit.count().unitDivided(by: .minute())
                if let value = statistics?.mostRecentQuantity()?.doubleValue(for: heartRateUnit) {
                    Task { @MainActor in
                        self.manager?.handleHeartRateUpdate(value)
                    }
                }
            }

            // Active calories
            if quantityType == HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
                let calorieUnit = HKUnit.kilocalorie()
                if let value = statistics?.sumQuantity()?.doubleValue(for: calorieUnit) {
                    Task { @MainActor in
                        self.manager?.handleCaloriesUpdate(value)
                    }
                }
            }
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Handle workout events if needed
    }
}
