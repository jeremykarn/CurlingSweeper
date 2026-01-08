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
        }
    }

    /// Send CSV data to iPhone
    func sendDebugData(_ csvData: String, fileName: String) {
        guard let session = session, session.isReachable else {
            lastSendStatus = "iPhone not reachable"
            return
        }

        let message: [String: Any] = [
            "debugCSV": csvData,
            "fileName": fileName
        ]

        session.sendMessage(message, replyHandler: nil) { [weak self] error in
            Task { @MainActor in
                self?.lastSendStatus = "Failed: \(error.localizedDescription)"
            }
        }

        lastSendStatus = "Sent \(csvData.count) bytes"
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isPhoneReachable = session.isReachable
        }

        if let error = error {
            print("WCSession activation failed: \(error.localizedDescription)")
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isPhoneReachable = session.isReachable
        }
    }
}
