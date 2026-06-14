import SwiftUI

// MARK: - Stats Data

struct ShelveStats {
    struct DayCount: Identifiable {
        let id = UUID()
        let label: String   // "Mon", "Tue", etc.
        let date: Date
        var count: Int
    }

    var totalMoves: Int = 0
    var movesThisWeek: Int = 0
    var movesToday: Int = 0
    var topDestinations: [(name: String, count: Int)] = []
    var topExtensions: [(ext: String, count: Int)] = []
    var dailyCounts: [DayCount] = []
}

// MARK: - Stats View

struct StatsMainView: View {
    @State private var stats = ShelveStats()
    @State private var lastRefresh = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Header
                HStack {
                    Text("Stats")
                        .font(.title3.bold())
                    Spacer()
                    Button {
                        stats = ConfigManager.shared.computeStats()
                        lastRefresh = Date()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Refresh stats")
                }
                .padding(.top, 4)

                // Summary cards
                HStack(spacing: 12) {
                    StatCard(value: "\(stats.totalMoves)", label: "Total Moves",
                             icon: "arrow.right.circle.fill", color: .blue)
                    StatCard(value: "\(stats.movesThisWeek)", label: "This Week",
                             icon: "calendar.circle.fill", color: .purple)
                    StatCard(value: "\(stats.movesToday)", label: "Today",
                             icon: "sun.max.circle.fill", color: .orange)
                }

                // Activity bar chart (last 7 days)
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Activity — last 7 days")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)

                        if stats.dailyCounts.isEmpty || stats.dailyCounts.allSatisfy({ $0.count == 0 }) {
                            Text("No moves in the last 7 days")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 20)
                        } else {
                            BarChart(data: stats.dailyCounts)
                                .frame(height: 90)
                        }
                    }
                    .padding(12)
                }

                // Top destinations
                if !stats.topDestinations.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Top Destinations")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)

                            let maxCount = stats.topDestinations.first?.count ?? 1
                            ForEach(stats.topDestinations, id: \.name) { dest in
                                HStack(spacing: 8) {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.accentColor)
                                        .frame(width: 16)
                                    Text(dest.name)
                                        .font(.system(size: 12))
                                        .frame(width: 90, alignment: .leading)
                                    GeometryReader { geo in
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.accentColor.opacity(0.25))
                                            .frame(width: max(4, geo.size.width * CGFloat(dest.count) / CGFloat(maxCount)))
                                    }
                                    .frame(height: 12)
                                    Text("\(dest.count)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(width: 28, alignment: .trailing)
                                }
                            }
                        }
                        .padding(12)
                    }
                }

                // Top file types
                if !stats.topExtensions.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Top File Types")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)

                            let cols = min(3, stats.topExtensions.count)
                            let rows = (stats.topExtensions.count + cols - 1) / cols

                            VStack(spacing: 6) {
                                ForEach(0..<rows, id: \.self) { row in
                                    HStack(spacing: 8) {
                                        ForEach(0..<cols, id: \.self) { col in
                                            let idx = row * cols + col
                                            if idx < stats.topExtensions.count {
                                                let e = stats.topExtensions[idx]
                                                ExtTag(ext: e.ext, count: e.count)
                                            } else {
                                                Spacer()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(12)
                    }
                }

                // Empty state
                if stats.totalMoves == 0 {
                    Spacer(minLength: 40)
                    VStack(spacing: 12) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.2))
                        Text("No data yet")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("Classify some files to see your stats here.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }

                Spacer(minLength: 8)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { stats = ConfigManager.shared.computeStats() }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.07))
        )
    }
}

// MARK: - Bar Chart

struct BarChart: View {
    let data: [ShelveStats.DayCount]

    var maxCount: Int { data.map(\.count).max() ?? 1 }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(data) { day in
                VStack(spacing: 4) {
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(day.count > 0 ? Color.accentColor : Color.secondary.opacity(0.15))
                        .frame(height: max(4, CGFloat(day.count) / CGFloat(maxCount) * 68))
                    Text(day.label)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Extension Tag

struct ExtTag: View {
    let ext: String
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Text(ext)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.accentColor)
            Spacer()
            Text("\(count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.08))
        )
    }
}
