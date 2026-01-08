//
//  CurlingSweeper_iOSApp.swift
//  CurlingSweeper iOS
//
//  Companion app for the Curling Sweeper watch app.
//

import SwiftUI

@main
struct CurlingSweeper_iOSApp: App {
    @State private var connectivityManager = PhoneConnectivityManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(connectivityManager)
        }
    }
}
