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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(workoutManager)
        }
    }
}
