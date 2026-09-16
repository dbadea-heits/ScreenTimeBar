import Charts
import SwiftUI

struct WeekCard: View {
    let week: [DayReport]

    private var totalSecs: Int {
        week.reduce(0) { $0 + $1.totalSecs }
    }

    /// Mean weighted score across days that actually have activity; empty days
    /// would otherwise drag the average to zero.
    private var avgText: String {
        let active = week.filter { $0.totalSecs > 0 }
        guard !active.isEmpty else { return "—" }
        let mean = active.reduce(0.0) { $0 + $1.weightedScore } / Double(active.count)
        return String(format: "%.1f", mean)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("Total \(fmtHM(totalSecs)) · Avg \(avgText)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if week.isEmpty {
                Text("No week data")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 90)
            } else {
                chart
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var chart: some View {
        Chart(week) { day in
            BarMark(
                x: .value("Day", weekdayShort(day.day)),
                y: .value("Hours", Double(day.totalSecs) / 3600)
            )
            .foregroundStyle(scoreColor(day.weightedScore))
        }
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .font(.caption2)
        .frame(height: 90)
    }
}
