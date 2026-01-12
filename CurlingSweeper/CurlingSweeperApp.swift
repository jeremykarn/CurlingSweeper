//
//  CurlingSweeperApp.swift
//  CurlingSweeper
//
//  Created by JEREMY KARN on 2025-12-21.
//

import SwiftUI

@main
struct CurlingSweeperApp: App {
    @State private var workoutManager = WorkoutManager()
    @State private var connectivityManager = WatchConnectivityManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(workoutManager)
                .environment(connectivityManager)
                .onAppear {
                    // Wire up status sync to phone
                    workoutManager.onStatusUpdate = { isActive, elapsed, calories, heartRate, strokes, end in
                        connectivityManager.syncWorkoutStatus(
                            isActive: isActive,
                            elapsedTime: elapsed,
                            calories: calories,
                            heartRate: heartRate,
                            strokeCount: strokes,
                            currentEnd: end
                        )
                    }
                    // Wire up debug data auto-upload
                    workoutManager.onSendDebugData = { csv, fileName in
                        connectivityManager.sendDebugData(csv, fileName: fileName)
                    }
                }
        }
    }
}
