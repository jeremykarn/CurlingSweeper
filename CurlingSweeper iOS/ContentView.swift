//
//  ContentView.swift
//  CurlingSweeper iOS
//
//  Companion app for receiving and sharing debug accelerometer data from watch.
//

import SwiftUI
import Charts

// MARK: - Accelerometer Data Point

struct AccelDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Double
    let x: Double
    let y: Double
    let z: Double
    let vx: Double
    let vy: Double
    let vz: Double
    let strokes: Int
}

enum AccelAxis: String, CaseIterable {
    case x = "X"
    case y = "Y"
    case z = "Z"

    var color: Color {
        switch self {
        case .x: return .red
        case .y: return .green
        case .z: return .blue
        }
    }
}

struct ContentView: View {
    @Environment(PhoneConnectivityManager.self) var connectivityManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Browse saved files button
                NavigationLink {
                    DebugFileBrowserView()
                } label: {
                    Label("Browse Saved Files", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

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
                        Image(systemName: connectivityManager.isConnected ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                            .font(.title)
                            .foregroundStyle(connectivityManager.isConnected ? .green : .secondary)

                        Text(connectivityManager.connectionStatus)
                            .foregroundStyle(connectivityManager.isConnected ? .primary : .secondary)
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

                        Text("\(connectivityManager.debugSampleCount) samples")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let savedURL = connectivityManager.savedFileURL {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Saved to Files app")
                                    .font(.caption)
                            }
                            Text(savedURL.lastPathComponent)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
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

// MARK: - Debug File Browser View

struct DebugFileBrowserView: View {
    @Environment(PhoneConnectivityManager.self) var connectivityManager
    @State private var chartData: [AccelDataPoint] = []
    @State private var visibleDomainLength: Double = 4.0  // Seconds visible on screen
    @State private var lastScaleValue: CGFloat = 1.0

    /// Timestamps where stroke count changes
    private var strokeChangeTimestamps: [Double] {
        var timestamps: [Double] = []
        var lastStrokes = 0
        for point in chartData {
            if point.strokes != lastStrokes {
                timestamps.append(point.timestamp)
                lastStrokes = point.strokes
            }
        }
        return timestamps
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Pickers
                VStack(spacing: 12) {
                    // Workout Date picker
                    HStack {
                        Text("Workout")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Workout", selection: Binding(
                            get: { connectivityManager.selectedWorkoutDate ?? "" },
                            set: { if !$0.isEmpty { connectivityManager.selectWorkoutDate($0) } }
                        )) {
                            ForEach(connectivityManager.availableWorkoutDates, id: \.self) { date in
                                Text(connectivityManager.displayDate(for: date))
                                    .tag(date)
                            }
                        }
                        .labelsHidden()
                    }

                    // End picker
                    HStack {
                        Text("End")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("End", selection: Binding(
                            get: { connectivityManager.selectedEnd ?? 0 },
                            set: { connectivityManager.selectEnd($0) }
                        )) {
                            ForEach(connectivityManager.availableEnds, id: \.self) { end in
                                Text("End \(end)").tag(end)
                            }
                        }
                        .labelsHidden()
                        .disabled(connectivityManager.availableEnds.isEmpty)
                    }

                    // Shot picker
                    HStack {
                        Text("Shot")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Shot", selection: Binding(
                            get: { connectivityManager.selectedShot ?? 0 },
                            set: { connectivityManager.selectShot($0) }
                        )) {
                            ForEach(connectivityManager.availableShots, id: \.self) { shot in
                                Text("Shot \(shot)").tag(shot)
                            }
                        }
                        .labelsHidden()
                        .disabled(connectivityManager.availableShots.isEmpty)
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                // Shot type indicator
                if let fileInfo = connectivityManager.getSelectedFileInfo() {
                    HStack {
                        Image(systemName: fileInfo.shotType == .sweep ? "figure.curling" : "figure.bowling")
                            .font(.title2)
                            .foregroundStyle(fileInfo.shotType == .sweep ? .blue : .orange)
                        Text(fileInfo.shotType == .sweep ? "Sweep" : "Throw")
                            .font(.headline)
                            .foregroundStyle(fileInfo.shotType == .sweep ? .blue : .orange)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }

                // Chart
                if !chartData.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Accelerometer Data")
                                .font(.headline)
                            Spacer()
                            Text("\(chartData.count) samples")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // Legend
                        HStack(spacing: 16) {
                            ForEach(AccelAxis.allCases, id: \.self) { axis in
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(axis.color)
                                        .frame(width: 8, height: 8)
                                    Text(axis.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        Chart {
                            // Vertical lines where stroke count changes
                            ForEach(strokeChangeTimestamps, id: \.self) { timestamp in
                                RuleMark(x: .value("Stroke", timestamp))
                                    .foregroundStyle(.orange.opacity(0.7))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))
                            }

                            ForEach(chartData) { point in
                                LineMark(
                                    x: .value("Time", point.timestamp),
                                    y: .value("Acceleration", point.x),
                                    series: .value("Axis", "X")
                                )
                                .foregroundStyle(AccelAxis.x.color)
                                .lineStyle(StrokeStyle(lineWidth: 1))

                                LineMark(
                                    x: .value("Time", point.timestamp),
                                    y: .value("Acceleration", point.y),
                                    series: .value("Axis", "Y")
                                )
                                .foregroundStyle(AccelAxis.y.color)
                                .lineStyle(StrokeStyle(lineWidth: 1))

                                LineMark(
                                    x: .value("Time", point.timestamp),
                                    y: .value("Acceleration", point.z),
                                    series: .value("Axis", "Z")
                                )
                                .foregroundStyle(AccelAxis.z.color)
                                .lineStyle(StrokeStyle(lineWidth: 1))
                            }
                        }
                        .chartXAxisLabel("Time (s)")
                        .chartYAxisLabel("Acceleration (g)")
                        .chartScrollableAxes(.horizontal)
                        .chartXVisibleDomain(length: visibleDomainLength)
                        .frame(height: 300)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastScaleValue
                                    lastScaleValue = value
                                    // Pinch out = zoom in (smaller domain), pinch in = zoom out (larger domain)
                                    let newLength = visibleDomainLength / delta
                                    // Clamp between 1 second and total duration
                                    let maxDomain = max(chartData.last?.timestamp ?? 30, 30)
                                    visibleDomainLength = min(max(newLength, 1), maxDomain)
                                }
                                .onEnded { _ in
                                    lastScaleValue = 1.0
                                }
                        )

                        // Zoom level indicator
                        HStack {
                            Image(systemName: "minus.magnifyingglass")
                                .foregroundStyle(.secondary)
                            Slider(value: $visibleDomainLength, in: 1...(chartData.last?.timestamp ?? 30))
                            Image(systemName: "plus.magnifyingglass")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                    // Velocity Chart
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Velocity (Estimated)")
                                .font(.headline)
                            Spacer()
                            Text("m/s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // Legend
                        HStack(spacing: 16) {
                            ForEach(AccelAxis.allCases, id: \.self) { axis in
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(axis.color)
                                        .frame(width: 8, height: 8)
                                    Text("V\(axis.rawValue.lowercased())")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        Chart {
                            ForEach(chartData) { point in
                                LineMark(
                                    x: .value("Time", point.timestamp),
                                    y: .value("Velocity", point.vx),
                                    series: .value("Axis", "VX")
                                )
                                .foregroundStyle(AccelAxis.x.color)
                                .lineStyle(StrokeStyle(lineWidth: 1))

                                LineMark(
                                    x: .value("Time", point.timestamp),
                                    y: .value("Velocity", point.vy),
                                    series: .value("Axis", "VY")
                                )
                                .foregroundStyle(AccelAxis.y.color)
                                .lineStyle(StrokeStyle(lineWidth: 1))

                                LineMark(
                                    x: .value("Time", point.timestamp),
                                    y: .value("Velocity", point.vz),
                                    series: .value("Axis", "VZ")
                                )
                                .foregroundStyle(AccelAxis.z.color)
                                .lineStyle(StrokeStyle(lineWidth: 1))
                            }
                        }
                        .chartXAxisLabel("Time (s)")
                        .chartYAxisLabel("Velocity (m/s)")
                        .chartScrollableAxes(.horizontal)
                        .chartXVisibleDomain(length: visibleDomainLength)
                        .frame(height: 200)
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                    // Stats
                    if let lastPoint = chartData.last {
                        HStack {
                            VStack {
                                Text("\(lastPoint.strokes)")
                                    .font(.title2.bold())
                                Text("Strokes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack {
                                Text(String(format: "%.1f s", chartData.last?.timestamp ?? 0))
                                    .font(.title2.bold())
                                Text("Duration")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }

                    // Share button
                    if let url = connectivityManager.getSelectedFileURL() {
                        ShareLink(item: url) {
                            Label("Share CSV", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if connectivityManager.availableWorkoutDates.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No Debug Files Found")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Enable debug mode on the watch\nand complete some shots")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .padding()
        }
        .navigationTitle("Debug Files")
        .onAppear {
            connectivityManager.scanDebugFiles()
            parseCSVData()
        }
        .onChange(of: connectivityManager.selectedFileContent) {
            parseCSVData()
        }
    }

    private func parseCSVData() {
        guard let content = connectivityManager.selectedFileContent else {
            chartData = []
            return
        }

        let lines = content.components(separatedBy: "\n")
        var parsed: [AccelDataPoint] = []

        // Skip header line
        // CSV format: timestamp,x,y,z,vx,vy,vz,strokes
        for line in lines.dropFirst() {
            let values = line.components(separatedBy: ",")
            guard values.count >= 8,
                  let timestamp = Double(values[0]),
                  let x = Double(values[1]),
                  let y = Double(values[2]),
                  let z = Double(values[3]),
                  let vx = Double(values[4]),
                  let vy = Double(values[5]),
                  let vz = Double(values[6]),
                  let strokes = Int(values[7]) else {
                continue
            }
            parsed.append(AccelDataPoint(timestamp: timestamp, x: x, y: y, z: z, vx: vx, vy: vy, vz: vz, strokes: strokes))
        }

        chartData = parsed
    }
}

#Preview {
    ContentView()
        .environment(PhoneConnectivityManager())
}
