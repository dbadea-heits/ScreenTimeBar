import SwiftUI

struct TodayCard: View {
    let report: DayReport

    /// Identifiable wrapper: `topApps` yields tuples, and Swift key paths
    /// cannot address tuple elements, so `ForEach` needs a named type.
    private struct AppRow: Identifiable {
        let id: String
        let secs: Int
        let score: Int
    }

    private var rows: [AppRow] {
        report.topApps(limit: 5).map { AppRow(id: $0.key, secs: $0.secs, score: $0.score) }
    }

    /// 0...1 share of the 0–10 score scale. Clamped so a stray score cannot
    /// overflow the track.
    private var scoreFraction: Double {
        min(1, max(0, report.weightedScore / 10))
    }

    private var bandTotal: Int {
        report.productiveSecs + report.neutralSecs + report.unprodSecs
    }

    private func bandFraction(_ secs: Int) -> Double {
        bandTotal > 0 ? Double(secs) / Double(bandTotal) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            scoreRow
            scoreTrack
            VStack(alignment: .leading, spacing: 6) {
                splitBar
                legend
            }
            topApps
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Score

    private var scoreRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(String(format: "%.1f", report.weightedScore))
                .font(.system(size: 34, weight: .semibold).monospacedDigit())
                .foregroundStyle(scoreColor(report.weightedScore))
            Text("/ 10")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text("Total \(fmtHM(report.totalSecs))")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private var scoreTrack: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.15))
                Capsule()
                    .fill(scoreColor(report.weightedScore))
                    .frame(width: geo.size.width * scoreFraction)
            }
        }
        .frame(height: 6)
    }

    // MARK: - Productive / neutral / unproductive split

    private var splitBar: some View {
        GeometryReader { geo in
            if bandTotal > 0 {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: geo.size.width * bandFraction(report.productiveSecs))
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: geo.size.width * bandFraction(report.neutralSecs))
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: geo.size.width * bandFraction(report.unprodSecs))
                    Spacer(minLength: 0)
                }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
            }
        }
        .frame(height: 8)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var legend: some View {
        (bullet(.green)
            + Text(" Prod \(fmtHM(report.productiveSecs))")
            + Text("  ·  ")
            + bullet(.orange)
            + Text(" Neutral \(fmtHM(report.neutralSecs))")
            + Text("  ·  ")
            + bullet(.red)
            + Text(" Unprod \(fmtHM(report.unprodSecs))"))
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bullet(_ color: Color) -> Text {
        Text("●").foregroundStyle(color)
    }

    // MARK: - Top apps

    private var topApps: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Top apps")
                .font(.caption)
                .foregroundStyle(.secondary)
            if rows.isEmpty {
                Text("No activity recorded today")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(rows) { row in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(scoreColor(row.score))
                            .frame(width: 8, height: 8)
                        Text(displayName(row.id))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 8)
                        Text(fmtHM(row.secs))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }
}
