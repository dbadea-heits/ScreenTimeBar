import Foundation
import SwiftUI

@MainActor
final class ScreenTimeStore: ObservableObject {
    enum Phase {
        case idle
        case loading
        case ready
        case failed(String)
    }

    @Published var today: DayReport?
    @Published var week: [DayReport] = []
    @Published var config: ScoresConfig?
    @Published var phase: Phase = .idle
    @Published var lastUpdated: Date?

    /// Set by `AppDelegate` to mirror the current score into the status item.
    var onLabelChange: ((_ title: String?, _ symbol: String) -> Void)?

    private var loading = false

    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Dates

    /// The seven local dates ending today, oldest first, as `yyyy-MM-dd`.
    func last7Days() -> [String] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }.map { dayFormatter.string(from: $0) }
    }

    // MARK: - Loading

    /// Re-reads the DB and re-scores today + the week. Keeps the last good data
    /// on screen while loading and on failure.
    func reload() {
        if loading { return }
        loading = true
        phase = .loading

        let cfg = ConfigFile.load()
        let days = last7Days()
        guard let from = days.first, let to = days.last else {
            loading = false
            phase = .failed("Could not compute the current date range.")
            updateLabel()
            return
        }

        Task {
            do {
                let rows = try await Task.detached {
                    try ScreenTimeDB.read(from: from, to: to)
                }.value
                self.config = cfg
                self.week = days.map {
                    Scorer.score(day: $0, seconds: rows[$0] ?? [:], config: cfg)
                }
                self.today = self.week.last
                self.lastUpdated = Date()
                self.phase = .ready
            } catch {
                // Keep prior `today`/`week`/`config` so the popover stays useful.
                self.phase = .failed((error as? LocalizedError)?.errorDescription ?? "\(error)")
            }
            self.loading = false
            self.updateLabel()
        }
    }

    func updateLabel() {
        guard let onLabelChange else { return }
        if let today {
            onLabelChange(String(format: "%.1f", today.weightedScore), "gauge.medium")
        } else if case .failed = phase {
            onLabelChange(nil, "exclamationmark.triangle")
        } else {
            onLabelChange(nil, "gauge.medium")
        }
    }

    // MARK: - Weights

    /// Every app worth showing in the weights editor: everything already in
    /// `scores.ini` plus everything seen in the last week, busiest first.
    func knownApps() -> [String] {
        var totals: [String: Int] = [:]
        for report in week {
            for (app, secs) in report.byApp {
                totals[app, default: 0] += secs
            }
        }
        var keys = Set(totals.keys)
        if let scores = config?.scores {
            for key in scores.keys where key != "default" {
                keys.insert(key)
            }
        }
        return keys.sorted { lhs, rhs in
            let l = totals[lhs] ?? 0
            let r = totals[rhs] ?? 0
            if l != r { return l > r }
            switch displayName(lhs).localizedCaseInsensitiveCompare(displayName(rhs)) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return lhs < rhs
            }
        }
    }

    /// Writes the edited weights back to `scores.ini`, then re-scores the
    /// already-loaded seconds in memory — the raw data is unchanged, so this
    /// never touches the DB.
    ///
    /// Only keys that carry information are written: `default` always, keys the
    /// file already lists (rewritten in place), and new keys whose value differs
    /// from `default`. Materialising every known app at the default value would
    /// bloat the file and pin those apps, so a later `default` change would no
    /// longer apply to them.
    func saveWeights(_ edits: [String: Int], default def: Int) throws {
        let existing = config?.scores ?? [:]
        var cfg = config ?? ScoresConfig.parse("")
        cfg.set("default", def)
        for (key, value) in edits where key != "default" {
            guard existing[key] != nil || value != def else { continue }
            cfg.set(key, value)
        }
        try ConfigFile.save(cfg)
        config = cfg
        week = week.map { Scorer.score(day: $0.day, seconds: $0.byApp, config: cfg) }
        today = week.last
        updateLabel()
    }
}
