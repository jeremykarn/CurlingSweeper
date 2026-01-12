//
//  WatchConnectivityManager.swift
//  CurlingSweeper
//
//  Handles WatchConnectivity to send debug data to the iPhone app.
//

import Foundation
import WatchConnectivity
import Observation

@Observable
@MainActor
final class WatchConnectivityManager: NSObject {

    var isPhoneReachable = false
    var lastSendStatus: String?

    private var session: WCSession?

    override init() {
        super.init()

        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
            print("WCSession activating...")
        } else {
            print("WCSession not supported")
        }
    }

    /// Send CSV data to iPhone - uses transferUserInfo for reliable background delivery
    func sendDebugData(_ csvData: String, fileName: String) {
        guard let session = session else {
            lastSendStatus = "No session"
            return
        }

        let userInfo: [String: Any] = [
            "debugCSV": csvData,
            "fileName": fileName
        ]

        // Use transferUserInfo - queued for delivery even if not reachable
        session.transferUserInfo(userInfo)
        lastSendStatus = "Queued \(csvData.count) bytes"
    }

    /// Sync workout status to iPhone
    func syncWorkoutStatus(isActive: Bool, elapsedTime: TimeInterval, calories: Double, heartRate: Double, strokeCount: Int, currentEnd: Int) {
        guard let session = session else { return }

        let data: [String: Any] = [
            "type": "workoutStatus",
            "isWorkoutActive": isActive,
            "elapsedTime": elapsedTime,
            "calories": calories,
            "heartRate": heartRate,
            "strokeCount": strokeCount,
            "currentEnd": currentEnd
        ]

        // Use sendMessage for real-time updates when reachable
        if session.isReachable {
            session.sendMessage(data, replyHandler: nil) { error in
                print("sendMessage error: \(error.localizedDescription)")
            }
        } else {
            // Fall back to application context for background sync
            do {
                try session.updateApplicationContext(data)
            } catch {
                print("Failed to update application context: \(error)")
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let reachable = session.isReachable

        print("WCSession activated: state=\(activationState.rawValue), reachable=\(reachable)")

        Task { @MainActor in
            self.isPhoneReachable = reachable
        }

        if let error = error {
            print("WCSession activation error: \(error.localizedDescription)")
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        print("WCSession reachability changed: \(session.isReachable)")
        Task { @MainActor in
            self.isPhoneReachable = session.isReachable
        }
    }
}
