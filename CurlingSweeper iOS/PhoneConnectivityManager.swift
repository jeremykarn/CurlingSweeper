//
//  PhoneConnectivityManager.swift
//  CurlingSweeper iOS
//
//  Handles WatchConnectivity to receive debug data from the watch app.
//

import Foundation
import WatchConnectivity
import Observation

// MARK: - Debug File Info

enum ShotType: String {
    case sweep = "sweep"
    case `throw` = "throw"
    case unknown = "unknown"
}

struct DebugFileInfo: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let workoutDate: String  // yyyy-MM-dd_HH-mm
    let displayDate: String  // Formatted for display
    let end: Int
    let shot: Int
    let shotType: ShotType

    var fileName: String { url.lastPathComponent }
}

@Observable
@MainActor
final class PhoneConnectivityManager: NSObject {

    var isWatchReachable = false
    var isWatchPaired = false
    var isWatchAppInstalled = false
    var lastReceivedData: String?
    var lastReceivedDate: Date?
    var receivedFileName: String?

    // Cached parsed debug data
    var debugSampleCount: Int = 0
    var debugLastLines: [String] = []
    var savedFileURL: URL?

    // Workout status from watch
    var isWorkoutActive = false
    var elapsedTime: TimeInterval = 0
    var calories: Double = 0
    var heartRate: Double = 0
    var strokeCount: Int = 0
    var currentEnd: Int = 0
    var lastStatusUpdate: Date?

    // Debug file browser
    var debugFiles: [DebugFileInfo] = []
    var availableWorkoutDates: [String] = []
    var selectedWorkoutDate: String?
    var availableEnds: [Int] = []
    var selectedEnd: Int?
    var availableShots: [Int] = []
    var selectedShot: Int?
    var selectedFileContent: String?

    private var session: WCSession?

    override init() {
        super.init()

        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()

            // Load any cached application context
            if let context = session?.receivedApplicationContext, !context.isEmpty {
                Task { @MainActor in
                    self.updateWorkoutStatus(from: context)
                }
            }
        }
    }

    var connectionStatus: String {
        if !isWatchPaired {
            return "No Watch Paired"
        } else if !isWatchAppInstalled {
            return "Watch App Not Installed"
        } else if isWatchReachable {
            return "Watch Connected"
        } else {
            return "Watch App Installed"
        }
    }

    var isConnected: Bool {
        isWatchPaired && isWatchAppInstalled
    }

    func formattedElapsedTime() -> String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func getReceivedDataURL() -> URL? {
        guard let data = lastReceivedData else { return nil }

        let fileName = receivedFileName ?? "debug_accelerometer_\(Int(Date().timeIntervalSince1970)).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try data.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            print("Failed to write CSV file: \(error)")
            return nil
        }
    }

    func clearReceivedData() {
        lastReceivedData = nil
        lastReceivedDate = nil
        receivedFileName = nil
        debugSampleCount = 0
        debugLastLines = []
    }

    private func parseDebugData(_ csvData: String) {
        let lines = csvData.components(separatedBy: "\n")
        debugSampleCount = max(0, lines.count - 2) // Subtract header and trailing newline
        let dataLines = lines.dropFirst().filter { !$0.isEmpty }
        debugLastLines = Array(dataLines.suffix(10))
    }

    /// Saves CSV data to the Documents directory
    private func saveToDocuments(_ csvData: String, fileName: String?) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let name = fileName ?? "workout_\(Int(Date().timeIntervalSince1970)).csv"
        let fileURL = documentsURL.appendingPathComponent(name)

        do {
            try csvData.write(to: fileURL, atomically: true, encoding: .utf8)
            savedFileURL = fileURL
            print("Saved debug CSV to: \(fileURL.path)")
        } catch {
            print("Failed to save CSV to Documents: \(error)")
        }
    }

    // MARK: - Debug File Browser

    /// Scans Documents directory for workout debug files
    func scanDebugFiles() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

        do {
            let files = try FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            let csvFiles = files.filter { $0.pathExtension == "csv" }

            // Parse filenames: workout_[yyyy-MM-dd_HH-mm]_end-[N]_shot-[M]_[sweep|throw].csv
            let regex = try NSRegularExpression(pattern: #"workout_(\d{4}-\d{2}-\d{2}_\d{2}-\d{2})_end-(\d+)_shot-(\d+)_(sweep|throw)\.csv"#)

            var parsed: [DebugFileInfo] = []
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm"

            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "MMM d, yyyy h:mm a"

            for file in csvFiles {
                let filename = file.lastPathComponent
                let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)

                if let match = regex.firstMatch(in: filename, range: range) {
                    let dateRange = Range(match.range(at: 1), in: filename)!
                    let endRange = Range(match.range(at: 2), in: filename)!
                    let shotRange = Range(match.range(at: 3), in: filename)!
                    let typeRange = Range(match.range(at: 4), in: filename)!

                    let workoutDate = String(filename[dateRange])
                    let end = Int(filename[endRange]) ?? 0
                    let shot = Int(filename[shotRange]) ?? 0
                    let shotType = ShotType(rawValue: String(filename[typeRange])) ?? .unknown

                    var displayDate = workoutDate
                    if let date = dateFormatter.date(from: workoutDate) {
                        displayDate = displayFormatter.string(from: date)
                    }

                    parsed.append(DebugFileInfo(url: file, workoutDate: workoutDate, displayDate: displayDate, end: end, shot: shot, shotType: shotType))
                }
            }

            // Sort by date descending, then end, then shot
            debugFiles = parsed.sorted {
                if $0.workoutDate != $1.workoutDate { return $0.workoutDate > $1.workoutDate }
                if $0.end != $1.end { return $0.end < $1.end }
                return $0.shot < $1.shot
            }

            // Update available workout dates
            let dates = Set(debugFiles.map { $0.workoutDate })
            availableWorkoutDates = dates.sorted().reversed()

            // Auto-select first date if none selected
            if selectedWorkoutDate == nil && !availableWorkoutDates.isEmpty {
                selectWorkoutDate(availableWorkoutDates[0])
            } else if let date = selectedWorkoutDate {
                // Refresh ends for current selection
                updateAvailableEnds(for: date)
            }

        } catch {
            print("Failed to scan debug files: \(error)")
        }
    }

    /// Select a workout date and update available ends
    func selectWorkoutDate(_ date: String) {
        selectedWorkoutDate = date
        updateAvailableEnds(for: date)
    }

    private func updateAvailableEnds(for date: String) {
        let ends = Set(debugFiles.filter { $0.workoutDate == date }.map { $0.end })
        availableEnds = ends.sorted()

        // Auto-select first end if current selection is invalid
        if selectedEnd == nil || !availableEnds.contains(selectedEnd!) {
            if let firstEnd = availableEnds.first {
                selectEnd(firstEnd)
            } else {
                selectedEnd = nil
                availableShots = []
                selectedShot = nil
                selectedFileContent = nil
            }
        } else if let end = selectedEnd {
            updateAvailableShots(for: date, end: end)
        }
    }

    /// Select an end and update available shots
    func selectEnd(_ end: Int) {
        selectedEnd = end
        if let date = selectedWorkoutDate {
            updateAvailableShots(for: date, end: end)
        }
    }

    private func updateAvailableShots(for date: String, end: Int) {
        let shots = Set(debugFiles.filter { $0.workoutDate == date && $0.end == end }.map { $0.shot })
        availableShots = shots.sorted()

        // Auto-select first shot if current selection is invalid
        if selectedShot == nil || !availableShots.contains(selectedShot!) {
            if let firstShot = availableShots.first {
                selectShot(firstShot)
            } else {
                selectedShot = nil
                selectedFileContent = nil
            }
        } else if let shot = selectedShot {
            loadSelectedFile(date: date, end: end, shot: shot)
        }
    }

    /// Select a shot and load the file content
    func selectShot(_ shot: Int) {
        selectedShot = shot
        if let date = selectedWorkoutDate, let end = selectedEnd {
            loadSelectedFile(date: date, end: end, shot: shot)
        }
    }

    private func loadSelectedFile(date: String, end: Int, shot: Int) {
        guard let file = debugFiles.first(where: { $0.workoutDate == date && $0.end == end && $0.shot == shot }) else {
            selectedFileContent = nil
            return
        }

        do {
            selectedFileContent = try String(contentsOf: file.url, encoding: .utf8)
        } catch {
            print("Failed to load file: \(error)")
            selectedFileContent = nil
        }
    }

    /// Get display string for workout date
    func displayDate(for workoutDate: String) -> String {
        debugFiles.first { $0.workoutDate == workoutDate }?.displayDate ?? workoutDate
    }

    /// Get URL for currently selected file
    func getSelectedFileURL() -> URL? {
        getSelectedFileInfo()?.url
    }

    func getSelectedFileInfo() -> DebugFileInfo? {
        guard let date = selectedWorkoutDate, let end = selectedEnd, let shot = selectedShot else { return nil }
        return debugFiles.first { $0.workoutDate == date && $0.end == end && $0.shot == shot }
    }
}

// MARK: - WCSessionDelegate

extension PhoneConnectivityManager: WCSessionDelegate {

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        let reachable = session.isReachable

        print("WCSession activated: state=\(activationState.rawValue), paired=\(paired), installed=\(installed), reachable=\(reachable)")

        Task { @MainActor in
            self.isWatchPaired = paired
            self.isWatchAppInstalled = installed
            self.isWatchReachable = reachable
        }

        if let error = error {
            print("WCSession activation error: \(error.localizedDescription)")
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        print("WCSession became inactive")
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        print("WCSession deactivated")
        // Reactivate for switching watches
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isWatchReachable = session.isReachable
        }
    }

    // Receive message with CSV data or workout status
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            // Check message type
            if let type = message["type"] as? String, type == "workoutStatus" {
                self.updateWorkoutStatus(from: message)
            } else if let csvData = message["debugCSV"] as? String {
                let fileName = message["fileName"] as? String
                self.lastReceivedData = csvData
                self.lastReceivedDate = Date()
                self.receivedFileName = fileName
                self.parseDebugData(csvData)
                self.saveToDocuments(csvData, fileName: fileName)
                print("Received debug CSV message: \(csvData.count) characters, \(self.debugSampleCount) samples")
            }
        }
    }

    @MainActor
    private func updateWorkoutStatus(from data: [String: Any]) {
        if let isActive = data["isWorkoutActive"] as? Bool {
            self.isWorkoutActive = isActive
        }
        if let elapsed = data["elapsedTime"] as? TimeInterval {
            self.elapsedTime = elapsed
        }
        if let cal = data["calories"] as? Double {
            self.calories = cal
        }
        if let hr = data["heartRate"] as? Double {
            self.heartRate = hr
        }
        if let strokes = data["strokeCount"] as? Int {
            self.strokeCount = strokes
        }
        if let end = data["currentEnd"] as? Int {
            self.currentEnd = end
        }
        self.lastStatusUpdate = Date()
    }

    // Receive transferUserInfo data
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            if let csvData = userInfo["debugCSV"] as? String {
                let fileName = userInfo["fileName"] as? String
                self.lastReceivedData = csvData
                self.lastReceivedDate = Date()
                self.receivedFileName = fileName
                self.parseDebugData(csvData)
                self.saveToDocuments(csvData, fileName: fileName)
                print("Received debug CSV userInfo: \(csvData.count) characters, \(self.debugSampleCount) samples")
            }
        }
    }

    // Receive application context (workout status)
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.updateWorkoutStatus(from: applicationContext)
            print("Received workout status via context: elapsed=\(self.elapsedTime), active=\(self.isWorkoutActive)")
        }
    }

    // Receive file transfer
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        Task { @MainActor in
            do {
                let csvData = try String(contentsOf: file.fileURL, encoding: .utf8)
                let fileName = file.fileURL.lastPathComponent
                self.lastReceivedData = csvData
                self.lastReceivedDate = Date()
                self.receivedFileName = fileName
                self.parseDebugData(csvData)
                self.saveToDocuments(csvData, fileName: fileName)
                print("Received debug file: \(fileName)")
            } catch {
                print("Failed to read received file: \(error)")
            }
        }
    }
}
