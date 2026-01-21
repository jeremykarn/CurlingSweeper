//
//  ContentView.swift
//  CurlingSweeper
//
//  Created by JEREMY KARN on 2025-12-21.
//

import SwiftUI

struct ContentView: View {
    @Environment(WorkoutManager.self) var workoutManager

    var body: some View {
        if workoutManager.isWorkoutActive {
            if workoutManager.isPaused {
                PausedSummaryView()
            } else {
                WorkoutView()
            }
        } else {
            StartView()
        }
    }
}

// MARK: - Start View

struct StartView: View {
    @Environment(WorkoutManager.self) var workoutManager
    @State private var isAuthorizing = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.curling")
                .font(.system(size: 50))
                .foregroundStyle(.blue)

            Text("Curling Sweeper")
                .font(.headline)

            Button {
                Task {
                    isAuthorizing = true
                    let authorized = await workoutManager.requestAuthorization()
                    if authorized {
                        await workoutManager.startWorkout()
                    }
                    isAuthorizing = false
                }
            } label: {
                Text("Start")
                    .font(.title3)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(isAuthorizing)
        }
        .padding()
    }
}

// MARK: - Workout View

struct WorkoutView: View {
    @Environment(WorkoutManager.self) var workoutManager
    @State private var showingEndConfirmation = false
    @State private var showingShotTimer = false

    var body: some View {
        VStack(spacing: 8) {
            // Ready for Shot button
            Button {
                showingShotTimer = true
            } label: {
                Text("Ready for Shot")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)

            // Stats grid
            VStack(spacing: 8) {
                // Row 1: End, Calories, Strokes
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text("\(workoutManager.currentEnd)")
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        Text("End")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 2) {
                        HStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text(workoutManager.activeCalories > 0
                                 ? "\(Int(workoutManager.activeCalories))"
                                 : "--")
                                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        }
                        Text("kcal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 2) {
                        Text("\(workoutManager.strokeCountEnd)")
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.cyan)
                        Text("Strokes")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }

                // Row 2: Elapsed and Heart Rate
                HStack(spacing: 32) {
                    VStack(spacing: 2) {
                        Text(workoutManager.formattedElapsedTime())
                            .font(.system(size: 16, design: .monospaced))
                        Text("Elapsed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                            Text(workoutManager.heartRate > 0
                                 ? "\(Int(workoutManager.heartRate))"
                                 : "--")
                                .font(.system(size: 16, design: .monospaced))
                        }
                        Text("BPM")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Spacer()

            // Controls
            HStack(spacing: 12) {
                // New End Button
                Button {
                    workoutManager.markNewEnd()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
                .tint(.blue)

                // Pause/Resume Button
                Button {
                    if workoutManager.isPaused {
                        workoutManager.resumeWorkout()
                    } else {
                        workoutManager.pauseWorkout()
                    }
                } label: {
                    Image(systemName: workoutManager.isPaused ? "play.fill" : "pause.fill")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
                .tint(.yellow)

                // End Workout Button
                Button {
                    showingEndConfirmation = true
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding()
        .fullScreenCover(isPresented: $showingShotTimer) {
            ShotTimerView(isPresented: $showingShotTimer)
        }
        .confirmationDialog("End Workout?", isPresented: $showingEndConfirmation) {
            Button("Save") {
                Task {
                    await workoutManager.endWorkout()
                }
            }
            Button("Discard", role: .destructive) {
                Task {
                    await workoutManager.discardWorkout()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Shot Tracking View

struct ShotTimerView: View {
    @Environment(WorkoutManager.self) var workoutManager
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Tracking Strokes")
                .font(.title2)
                .foregroundStyle(.green)

            Text("\(workoutManager.strokeCountEnd)")
                .font(.system(size: 72, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan)

            Text("strokes this end")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                workoutManager.endShot()
                isPresented = false
            } label: {
                Text("Shot Ended")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear {
            workoutManager.startShot()
        }
        .onDisappear {
            // Ensure shot ends if view is dismissed another way
            if workoutManager.isShotActive {
                workoutManager.endShot()
            }
        }
    }
}

// MARK: - Paused Summary View

struct PausedSummaryView: View {
    @Environment(WorkoutManager.self) var workoutManager
    @Environment(WatchConnectivityManager.self) var connectivityManager

    var body: some View {
        @Bindable var manager = workoutManager

        ScrollView {
            VStack(spacing: 12) {
                Text("Workout Paused")
                    .font(.headline)
                    .foregroundStyle(.yellow)

                VStack(spacing: 8) {
                    // Elapsed Time
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundStyle(.blue)
                        Text("Elapsed")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(workoutManager.formattedElapsedTime())
                            .font(.system(.caption, design: .monospaced))
                    }

                    // Active Calories
                    HStack {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text("Calories")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(workoutManager.activeCalories)) kcal")
                            .font(.system(.caption, design: .monospaced))
                    }

                    // Total Strokes
                    HStack {
                        Image(systemName: "figure.curling")
                            .foregroundStyle(.cyan)
                        Text("Strokes")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(workoutManager.strokeCountTotal)")
                            .font(.system(.caption, design: .monospaced))
                    }

                    // Average Heart Rate
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                        Text("Avg HR")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(workoutManager.averageHeartRate > 0
                             ? "\(Int(workoutManager.averageHeartRate)) BPM"
                             : "-- BPM")
                            .font(.system(.caption, design: .monospaced))
                    }
                }

                Divider()

                // Debug section
                VStack(spacing: 8) {
                    Toggle("Debug Log", isOn: $manager.isDebugMode)
                        .font(.caption)

                    if workoutManager.hasDebugData {
                        Text("\(workoutManager.debugSampleCount) samples")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Button {
                            let csv = workoutManager.getDebugCSV()
                            let formatter = DateFormatter()
                            formatter.dateFormat = "yyyy-MM-dd_HH-mm"
                            let dateStr = formatter.string(from: Date())
                            let fileName = "workout_\(dateStr)_end-\(workoutManager.currentEnd)_shot-\(workoutManager.currentShotInEnd).csv"
                            connectivityManager.sendDebugData(csv, fileName: fileName)
                        } label: {
                            Label("Send to iPhone", systemImage: "iphone.and.arrow.forward")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(.purple)

                        if let status = connectivityManager.lastSendStatus {
                            Text(status)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else if workoutManager.isDebugMode {
                        Text("Recording during shots")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // Resume button
                Button {
                    workoutManager.resumeWorkout()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
        .environment(WorkoutManager())
}
