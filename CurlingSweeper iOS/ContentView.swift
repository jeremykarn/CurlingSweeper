//
//  ContentView.swift
//  CurlingSweeper iOS
//
//  Companion app for receiving and sharing debug accelerometer data from watch.
//

import SwiftUI

struct ContentView: View {
    @Environment(PhoneConnectivityManager.self) var connectivityManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Watch connection status
                HStack {
                    Image(systemName: connectivityManager.isWatchReachable ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                        .font(.title)
                        .foregroundStyle(connectivityManager.isWatchReachable ? .green : .secondary)

                    Text(connectivityManager.isWatchReachable ? "Watch Connected" : "Watch Not Reachable")
                        .foregroundStyle(connectivityManager.isWatchReachable ? .primary : .secondary)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                Spacer()

                // Received data section
                if let csvData = connectivityManager.lastReceivedData {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)

                        Text("Debug Data Received")
                            .font(.headline)

                        if let date = connectivityManager.lastReceivedDate {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        let lineCount = csvData.components(separatedBy: "\n").count - 1
                        Text("\(lineCount) samples")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        // Share button
                        if let url = connectivityManager.getReceivedDataURL() {
                            ShareLink(item: url) {
                                Label("Share CSV", systemImage: "square.and.arrow.up")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Button(role: .destructive) {
                            connectivityManager.clearReceivedData()
                        } label: {
                            Label("Clear", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)

                        Text("No Debug Data")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Text("Enable debug mode on the watch app\nand send data after a workout")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Curling Sweeper")
        }
    }
}

#Preview {
    ContentView()
        .environment(PhoneConnectivityManager())
}
