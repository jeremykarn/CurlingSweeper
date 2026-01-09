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
                // Workout status
                if connectivityManager.isWorkoutActive {
                    VStack(spacing: 16) {
                        HStack {
                            Image(systemName: "figure.curling")
                                .font(.title)
                                .foregroundStyle(.green)
                            Text("Workout Active")
                                .font(.headline)
                                .foregroundStyle(.green)
                        }

                        // Elapsed time
                        Text(connectivityManager.formattedElapsedTime())
                            .font(.system(size: 64, weight: .bold, design: .monospaced))

                        // Stats row
                        HStack(spacing: 32) {
                            VStack {
                                Text("\(connectivityManager.currentEnd)")
                                    .font(.title2.bold())
                                Text("End")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            VStack {
                                Text("\(Int(connectivityManager.calories))")
                                    .font(.title2.bold())
                                Text("kcal")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            VStack {
                                Text("\(connectivityManager.strokeCount)")
                                    .font(.title2.bold())
                                Text("Strokes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            VStack {
                                Text(connectivityManager.heartRate > 0 ? "\(Int(connectivityManager.heartRate))" : "--")
                                    .font(.title2.bold())
                                Text("BPM")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                } else {
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
                }

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

                        let lines = csvData.components(separatedBy: "\n")
                        let lineCount = lines.count - 1
                        Text("\(lineCount) samples")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        // Last 10 lines preview
                        let dataLines = lines.dropFirst() // Skip header
                        let last10 = dataLines.suffix(10)
                        if !last10.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Last 10 samples:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(Array(last10.enumerated()), id: \.offset) { _, line in
                                    if !line.isEmpty {
                                        Text(line)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }

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
