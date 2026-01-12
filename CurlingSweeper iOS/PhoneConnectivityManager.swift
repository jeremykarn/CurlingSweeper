//
//  PhoneConnectivityManager.swift
//  CurlingSweeper iOS
//
//  Handles WatchConnectivity to receive debug data from the watch app.
//

import Foundation
import WatchConnectivity
import Observation

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

    // Workout status from watch
    var isWorkoutActive = false
    var elapsedTime: TimeInterval = 0
    var calories: Double = 0
    var heartRate: Double = 0
    var strokeCount: Int = 0
    var currentEnd: Int = 0
    var lastStatusUpdate: Date?

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
                self.lastReceivedData = csvData
                self.lastReceivedDate = Date()
                self.receivedFileName = message["fileName"] as? String
                self.parseDebugData(csvData)
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
                self.lastReceivedData = csvData
                self.lastReceivedDate = Date()
                self.receivedFileName = userInfo["fileName"] as? String
                self.parseDebugData(csvData)
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
                let data = try String(contentsOf: file.fileURL, encoding: .utf8)
                self.lastReceivedData = data
                self.lastReceivedDate = Date()
                self.receivedFileName = file.fileURL.lastPathComponent
                print("Received debug file: \(file.fileURL.lastPathComponent)")
            } catch {
                print("Failed to read received file: \(error)")
            }
        }
    }
}
