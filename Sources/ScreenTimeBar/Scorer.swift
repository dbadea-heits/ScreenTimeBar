import Foundation

enum Scorer {
    static func score(day: String, seconds: [String: Int], config: ScoresConfig) -> DayReport {
        var total = 0, num = 0, prod = 0, neut = 0, unp = 0
        var byAppScore: [String: Int] = [:]
        for (app, secs) in seconds {
            let sc = config.scores[app] ?? config.defaultScore
            byAppScore[app] = sc
            total += secs; num += secs * sc
            if sc >= 7 { prod += secs } else if sc >= 4 { neut += secs } else { unp += secs }
        }
        let weighted = total == 0 ? 0 : Double(num) / Double(total)
        return DayReport(day: day, byApp: seconds, byAppScore: byAppScore,
                         totalSecs: total, weightedScore: weighted,
                         productiveSecs: prod, neutralSecs: neut, unprodSecs: unp)
    }
}
