import Charts
import SwiftUI

struct WeekCard: View {
    let week: [DayReport]

    /// Day key ("yyyy-MM-dd") the popover is currently browsing; nil means today,
    /// which is the last element of `week`.
    let selectedDay: String?

    /// Hands the tapped bar's day key upward; the owner of the selection state
    /// decides what to do with it, this view never mutates anything.
    let onSelectDay: (String) -> Void

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

    /// `store.today == week.last`, so a nil selection highlights today without
    /// the chart needing to know the current date.
    private var highlightedDay: String? { selectedDay ?? week.last?.day }

    private var chart: some View {
        Chart(week) { day in
            BarMark(
                x: .value("Day", day.day),
                y: .value("Hours", Double(day.totalSecs) / 3600)
            )
            .foregroundStyle(scoreColor(day.weightedScore).opacity(day.day == highlightedDay ? 1 : 0.4))
        }
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let d = value.as(String.self) {
                        Text(weekdayShort(d))
                    }
                }
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
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture().onEnded { value in
                            guard let plotFrame = proxy.plotFrame else { return }
                            let rect = geo[plotFrame]
                            let x = value.location.x - rect.minX
                            guard x >= 0, x <= rect.width else { return }
                            if let day: String = proxy.value(atX: x) {
                                onSelectDay(day)
                            } else if !week.isEmpty {
                                let idx = min(week.count - 1, max(0, Int(x / (rect.width / CGFloat(week.count)))))
                                onSelectDay(week[idx].day)
                            }
                        }
                    )
            }
        }
    }
}
