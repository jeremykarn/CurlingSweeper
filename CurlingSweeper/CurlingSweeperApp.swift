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
        }
    }
}
