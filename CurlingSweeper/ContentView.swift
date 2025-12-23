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
            WorkoutView()
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

    var body: some View {
        @Bindable var manager = workoutManager

        VStack(spacing: 8) {
            // Stopwatch (main feature - tap to start/stop)
            VStack(spacing: 4) {
                Text(workoutManager.formattedStopwatchTime())
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .foregroundStyle(workoutManager.isStopwatchRunning ? .green : .primary)

                // Show estimate while running or after stopped
                if let estimate = workoutManager.currentEstimate {
                    Text(estimate.label)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.orange)
                } else {
                    Text(workoutManager.isStopwatchRunning ? "Timing..." : "Tap to time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                workoutManager.toggleStopwatch()
            }

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
        .sheet(isPresented: $manager.showPositionPicker) {
            PositionPickerView()
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

// MARK: - Position Picker View

struct PositionPickerView: View {
    @Environment(WorkoutManager.self) var workoutManager
    @Environment(\.dismiss) var dismiss

    // Common positions shown first
    private let quickPositions: [RockPosition] = [
        .hog, .weight4, .weight5, .weight6, .hit
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    // Time and estimate (compact)
                    HStack {
                        Text(workoutManager.formattedStopwatchTime())
                            .font(.system(size: 14, weight: .medium, design: .monospaced))

                        if let estimate = workoutManager.currentEstimate {
                            Text("→ \(estimate.label)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.orange)
                        }
                    }
                    .foregroundStyle(.secondary)

                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 8) {
                        ForEach(RockPosition.allCases) { position in
                            Button {
                                workoutManager.recordSplit(position: position)
                                dismiss()
                            } label: {
                                Text(position.label)
                                    .font(.system(size: 14, weight: .medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .tint(buttonColor(for: position))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Record Position")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        workoutManager.showPositionPicker = false
                        dismiss()
                    }
                }
            }
        }
    }

    private func buttonColor(for position: RockPosition) -> Color {
        switch position {
        case .hog:
            return .red
        case .weight1, .weight2, .weight3:
            return .blue
        case .weight4, .weight5, .weight6:
            return .green
        case .weight7, .weight8, .weight9, .weight10:
            return .orange
        case .hack, .board, .hit:
            return .purple
        }
    }
}

#Preview {
    ContentView()
        .environment(WorkoutManager())
}
