import SwiftUI

// MARK: - Durations

func fmtHM(_ secs: Int) -> String {
    let total = max(0, secs)
    let h = total / 3600
    let m = (total % 3600) / 60
    if h > 0 && m > 0 { return "\(h)h \(m)m" }
    if h > 0 { return "\(h)h" }
    return "\(m)m"
}

// MARK: - Score colors

func scoreColor(_ s: Double) -> Color {
    if s < 4 { return .red }
    if s < 7 { return .orange }
    return .green
}

func scoreColor(_ s: Int) -> Color {
    scoreColor(Double(s))
}

// MARK: - App names

private let appDisplayNames: [String: String] = [
    "slackmacgap": "Slack",
    "iterm2": "iTerm",
    "quicktimeplayerx": "QuickTime",
    "usernotificationcenter": "Notifications",
    "theunarchiver": "The Unarchiver",
    "loginwindow": "Idle / Lock",
    "ical": "Calendar",
    "google chrome": "Chrome",
    "brave browser": "Brave",
]

func displayName(_ key: String) -> String {
    if let mapped = appDisplayNames[key] { return mapped }
    guard !key.isEmpty else { return "" }
    return key.prefix(1).uppercased() + key.dropFirst()
}

// MARK: - Dates

private let dayParser: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

private let weekdayShortFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "EEE"
    return f
}()

private let longDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "EEE, MMM d"
    return f
}()

func weekdayShort(_ day: String) -> String {
    guard let date = dayParser.date(from: day) else { return day }
    return weekdayShortFormatter.string(from: date)
}

func longDate(_ day: String) -> String {
    guard let date = dayParser.date(from: day) else { return day }
    return longDateFormatter.string(from: date)
}
