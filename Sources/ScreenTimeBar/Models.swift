import Foundation

struct DayReport: Identifiable {
    let day: String
    let byApp: [String: Int]        // seconds per app (raw, from DB)
    let byAppScore: [String: Int]
    let totalSecs: Int
    let weightedScore: Double
    let productiveSecs: Int
    let neutralSecs: Int
    let unprodSecs: Int
    var id: String { day }
    func topApps(limit: Int) -> [(key: String, secs: Int, score: Int)] {
        byApp.sorted { $0.value > $1.value }.prefix(limit)
            .map { ($0.key, $0.value, byAppScore[$0.key] ?? 5) }
    }
}
