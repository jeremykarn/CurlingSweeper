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

// MARK: - Rock Position

enum RockPosition: Int, CaseIterable, Identifiable, Comparable {
    case hog = 0
    case weight1 = 1
    case weight2 = 2
    case weight3 = 3
    case weight4 = 4
    case weight5 = 5
    case weight6 = 6
    case weight7 = 7
    case weight8 = 8
    case weight9 = 9
    case weight10 = 10
    case hack = 11
    case board = 12
    case hit = 13

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .hog: return "HOG"
        case .weight1: return "1"
        case .weight2: return "2"
        case .weight3: return "3"
        case .weight4: return "4"
        case .weight5: return "5"
        case .weight6: return "6"
        case .weight7: return "7"
        case .weight8: return "8"
        case .weight9: return "9"
        case .weight10: return "10"
        case .hack: return "HACK"
        case .board: return "BOARD"
        case .hit: return "HIT"
        }
    }

    var description: String {
        switch self {
        case .hog: return "Hogged (didn't reach)"
        case .weight1, .weight2, .weight3, .weight4, .weight5,
             .weight6, .weight7, .weight8, .weight9, .weight10:
            return "Weight \(rawValue)"
        case .hack: return "Through to hack"
        case .board: return "Hit the board"
        case .hit: return "Takeout"
        }
    }

    static func < (lhs: RockPosition, rhs: RockPosition) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

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

    // Stopwatch properties
    var isStopwatchRunning = false
    var stopwatchTime: TimeInterval = 0

    // Rock position estimation
    var currentEstimate: RockPosition?
    var showPositionPicker = false

    // End tracking
    var currentEnd: Int = 0

    // Brush stroke counting
    var strokeCountEnd: Int = 0      // Strokes in current end
    var strokeCountTotal: Int = 0    // Total strokes in workout

    // Debug mode for accelerometer recording
    var isDebugMode = false
    var debugSampleCount: Int = 0
    var currentShotIndex: Int = 0
    private var nextShotIndex: Int = 0
    private var debugData: [(timestamp: TimeInterval, x: Double, y: Double, z: Double)] = []
    private var debugStartTime: Date?

    // Callback for syncing status to phone
    var onStatusUpdate: ((Bool, TimeInterval, Double, Double, Int, Int) -> Void)?
    private var lastSyncTime: Date?

    // MARK: - Private Properties

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startDate: Date?

    // Motion detection - Garmin algorithm
    private let motionManager = CMMotionManager()

    // Sweep detection thresholds
    // Lowered from Garmin's 1g - Apple Watch accelerometer may differ
    private let sweepThresholdY: Double = 0.3  // 0.3g threshold for sweep detection
    private let sweepWavelength: Int = 15      // Look back up to 15 samples for wave pattern (at 25Hz = 0.6 sec)
    private var yHistory: [Double] = []        // Recent Y acceleration samples
    private var lastStrokeSampleIndex: Int = -15  // Samples since last counted stroke
    private var timer: Timer?
    private var delegateHandler: WorkoutDelegateHandler?
    private var stopwatchStartDate: Date?

    // Split times in seconds (default values from Garmin app, converted from ms)
    // Index 0 = HOG, 1-10 = weights, 11 = HACK, 12 = BOARD, 13 = HIT
    private var splitTimes: [TimeInterval] = [
        99.999,  // HOG (essentially infinite - rock didn't make it)
        4.400,   // Weight 1
        4.300,   // Weight 2
        4.200,   // Weight 3
        4.100,   // Weight 4
        4.000,   // Weight 5
        3.900,   // Weight 6
        3.800,   // Weight 7
        3.700,   // Weight 8
        3.600,   // Weight 9
        3.500,   // Weight 10
        3.400,   // HACK
        3.300,   // BOARD
        3.200    // HIT
    ]

    // Recorded times (-1 means not yet recorded)
    private var recordedTimes: [TimeInterval] = Array(repeating: -1, count: 14)

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
        currentShotIndex = 0
        nextShotIndex = 0
        resetStopwatch()
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
        currentEnd += 1
        resetStopwatch()
        strokeCountEnd = 0  // Reset per-end stroke count
    }

    // MARK: - Brush Stroke Detection

    private func startMotionUpdates() {
        guard motionManager.isAccelerometerAvailable else {
            print("Accelerometer not available")
            return
        }

        motionManager.accelerometerUpdateInterval = 1.0 / 25.0  // 25Hz like Garmin app
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self = self, let data = data else { return }
            Task { @MainActor in
                self.processAccelerometerData(data)
            }
        }
    }

    private func stopMotionUpdates() {
        motionManager.stopAccelerometerUpdates()
        yHistory.removeAll()
        lastStrokeSampleIndex = -sweepWavelength
    }

    private func processAccelerometerData(_ data: CMAccelerometerData) {
        let xAccel = data.acceleration.x
        let yAccel = data.acceleration.y
        let zAccel = data.acceleration.z

        // Record debug data if enabled
        if isDebugMode {
            if debugStartTime == nil {
                debugStartTime = Date()
            }
            let timestamp = Date().timeIntervalSince(debugStartTime!)
            debugData.append((timestamp: timestamp, x: xAccel, y: yAccel, z: zAccel))
            debugSampleCount = debugData.count
        }

        // Add to history (keep last sweepWavelength * 2 samples for lookback)
        yHistory.append(yAccel)
        let maxHistory = sweepWavelength * 2
        if yHistory.count > maxHistory {
            yHistory.removeFirst(yHistory.count - maxHistory)
        }

        // Detect sweep using Garmin algorithm
        detectSweepGarmin()
    }

    /// Simplified stroke detection - counts when acceleration crosses threshold and reverses
    private func detectSweepGarmin() {
        let currentIndex = yHistory.count - 1
        guard currentIndex >= 0 else { return }

        let currentY = yHistory[currentIndex]

        // Only check if current acceleration exceeds threshold
        guard abs(currentY) > sweepThresholdY else { return }

        // Don't count if we recently counted a stroke
        guard currentIndex - lastStrokeSampleIndex >= 5 else { return }  // At least 5 samples (0.2 sec) between strokes

        let currentIsPositive = currentY > 0

        // Look back to find if we had opposite direction recently (simpler than full wave)
        for j in 1..<sweepWavelength {
            let lookbackIndex = currentIndex - j
            guard lookbackIndex >= 0 else { break }

            let prevY = yHistory[lookbackIndex]

            // Found a sample above threshold in opposite direction = one stroke
            if abs(prevY) > sweepThresholdY && (prevY > 0) != currentIsPositive {
                countStroke()
                lastStrokeSampleIndex = currentIndex
                return
            }
        }
    }

    private func countStroke() {
        strokeCountEnd += 1
        strokeCountTotal += 1
    }

    private func resetStrokeCount() {
        strokeCountEnd = 0
        strokeCountTotal = 0
        yHistory.removeAll()
        lastStrokeSampleIndex = -sweepWavelength
    }

    // MARK: - Debug Data

    /// Returns debug data as CSV string
    func getDebugCSV() -> String {
        var csv = "timestamp,x,y,z\n"
        for sample in debugData {
            csv += String(format: "%.4f,%.6f,%.6f,%.6f\n",
                          sample.timestamp, sample.x, sample.y, sample.z)
        }
        return csv
    }

    /// Clears all recorded debug data
    func clearDebugData() {
        debugData.removeAll()
        debugSampleCount = 0
        debugStartTime = nil
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

        // Update stopwatch if running
        if isStopwatchRunning, let stopwatchStart = stopwatchStartDate {
            stopwatchTime = Date().timeIntervalSince(stopwatchStart)
            updateEstimate()
        }

        // Sync status to phone every second
        if lastSyncTime == nil || Date().timeIntervalSince(lastSyncTime!) >= 1.0 {
            lastSyncTime = Date()
            onStatusUpdate?(isWorkoutActive, elapsedTime, activeCalories, heartRate, strokeCountTotal, currentEnd)
        }
    }

    // MARK: - Stopwatch

    func toggleStopwatch() {
        if isStopwatchRunning {
            // Stop the stopwatch, keep the time displayed
            isStopwatchRunning = false
            stopwatchStartDate = nil
            // Show position picker after delay (rock needs time to travel)
            if stopwatchTime > 0 {
                Task {
                    try? await Task.sleep(for: .seconds(10))
                    // Only show picker if we haven't started a new timing
                    if !isStopwatchRunning && !showPositionPicker {
                        showPositionPicker = true
                    }
                }
            }
        } else {
            // Start fresh stopwatch
            stopwatchTime = 0
            stopwatchStartDate = Date()
            isStopwatchRunning = true
            currentEstimate = nil
            showPositionPicker = false

            // Capture shot index and start debug recording
            currentShotIndex = nextShotIndex
            if isDebugMode {
                clearDebugData()
            }
        }
    }

    func resetStopwatch() {
        isStopwatchRunning = false
        stopwatchTime = 0
        stopwatchStartDate = nil
        currentEstimate = nil
    }

    // MARK: - Rock Position Estimation

    /// Returns the estimated rock position based on current stopwatch time
    func getStopwatchEstimate() -> RockPosition? {
        guard stopwatchTime > 0 else { return nil }

        // Find the position where the time is less than or equal to the split time
        // Faster times = further positions (lower split time index = shorter/slower)
        for i in stride(from: splitTimes.count - 1, through: 0, by: -1) {
            if stopwatchTime <= splitTimes[i] {
                return RockPosition(rawValue: i)
            }
        }
        return .hog
    }

    /// Updates the current estimate (called by timer)
    private func updateEstimate() {
        if isStopwatchRunning {
            currentEstimate = getStopwatchEstimate()
        }
    }

    /// Records where a rock actually stopped and adjusts future estimates
    func recordSplit(position: RockPosition) {
        guard stopwatchTime > 0 else { return }

        let index = position.rawValue
        let time = stopwatchTime

        // Increment shot index for next shot
        nextShotIndex += 1

        // Record this time for the position
        // For HOG: only record if faster than existing (rock was going faster than expected)
        // For HIT: only record if slower than existing
        // For other positions: always record
        if index > 0 && index < recordedTimes.count - 1 {
            recordedTimes[index] = time
        } else if index == 0 && (recordedTimes[index] < 0 || recordedTimes[index] > time) {
            recordedTimes[index] = time
        } else if index == recordedTimes.count - 1 && (recordedTimes[index] < 0 || recordedTimes[index] < time) {
            recordedTimes[index] = time
        }

        // Invalidate inconsistent records
        for i in 0..<recordedTimes.count {
            if i < index && recordedTimes[i] >= 0 && recordedTimes[i] <= time {
                // Faster time recorded for shorter throw - ice may have sped up
                recordedTimes[i] = -1
            }
            if i > index && recordedTimes[i] >= 0 && recordedTimes[i] >= time {
                // Slower time recorded for longer throw - ice may have slowed down
                recordedTimes[i] = -1
            }
        }

        // Recalculate split times based on recorded data
        recalculateSplitTimes()

        // Store the position in debug data filename for reference
        lastRecordedPosition = position

        // Hide picker and reset for next timing
        showPositionPicker = false
    }

    // Last recorded position for debug filename
    var lastRecordedPosition: RockPosition?

    /// Recalculates split times based on recorded observations
    private func recalculateSplitTimes() {
        var lastRecordedIndex = -1
        var averageDiff: TimeInterval = 0.100  // Default 100ms between positions

        for i in 0..<recordedTimes.count {
            if recordedTimes[i] > 0 {
                splitTimes[i] = recordedTimes[i]

                if lastRecordedIndex >= 0 {
                    // Calculate average time difference between recorded positions
                    averageDiff = (recordedTimes[lastRecordedIndex] - recordedTimes[i]) / Double(i - lastRecordedIndex)

                    // Fill in gaps between last recorded and current
                    for j in (lastRecordedIndex + 1)..<i {
                        splitTimes[j] = recordedTimes[lastRecordedIndex] - Double(j - lastRecordedIndex) * averageDiff
                    }
                } else if i > 0 {
                    // No previous record, extrapolate backwards
                    for j in stride(from: i - 1, through: 0, by: -1) {
                        splitTimes[j] = recordedTimes[i] + Double(i - j) * averageDiff
                    }
                }

                lastRecordedIndex = i
            }
        }

        // Extrapolate forward from last recorded position
        if lastRecordedIndex >= 0 && lastRecordedIndex < recordedTimes.count - 1 {
            for j in (lastRecordedIndex + 1)..<recordedTimes.count {
                splitTimes[j] = recordedTimes[lastRecordedIndex] - Double(j - lastRecordedIndex) * averageDiff
            }
        }
    }

    // MARK: - Formatting Helpers

    func formattedElapsedTime() -> String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        let tenths = Int((elapsedTime.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }

    func formattedStopwatchTime() -> String {
        let seconds = Int(stopwatchTime)
        let hundredths = Int((stopwatchTime.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d.%02d", seconds, hundredths)
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
