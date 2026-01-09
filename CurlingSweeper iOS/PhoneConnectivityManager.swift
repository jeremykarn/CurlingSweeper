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
    var lastReceivedData: String?
    var lastReceivedDate: Date?
    var receivedFileName: String?

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
        }
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
    }
}

// MARK: - WCSessionDelegate

extension PhoneConnectivityManager: WCSessionDelegate {

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isWatchReachable = session.isReachable
        }

        if let error = error {
            print("WCSession activation failed: \(error.localizedDescription)")
        } else {
            print("WCSession activated with state: \(activationState.rawValue)")
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

    // Receive message with CSV data
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            if let csvData = message["debugCSV"] as? String {
                self.lastReceivedData = csvData
                self.lastReceivedDate = Date()
                self.receivedFileName = message["fileName"] as? String
                print("Received debug CSV message: \(csvData.count) characters")
            }
        }
    }

    // Receive transferUserInfo data
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            if let csvData = userInfo["debugCSV"] as? String {
                self.lastReceivedData = csvData
                self.lastReceivedDate = Date()
                self.receivedFileName = userInfo["fileName"] as? String
                print("Received debug CSV userInfo: \(csvData.count) characters")
            }
        }
    }

    // Receive application context (workout status)
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            if let isActive = applicationContext["isWorkoutActive"] as? Bool {
                self.isWorkoutActive = isActive
            }
            if let elapsed = applicationContext["elapsedTime"] as? TimeInterval {
                self.elapsedTime = elapsed
            }
            if let cal = applicationContext["calories"] as? Double {
                self.calories = cal
            }
            if let hr = applicationContext["heartRate"] as? Double {
                self.heartRate = hr
            }
            if let strokes = applicationContext["strokeCount"] as? Int {
                self.strokeCount = strokes
            }
            if let end = applicationContext["currentEnd"] as? Int {
                self.currentEnd = end
            }
            self.lastStatusUpdate = Date()
            print("Received workout status: elapsed=\(self.elapsedTime), active=\(self.isWorkoutActive)")
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
