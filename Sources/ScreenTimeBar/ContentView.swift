import AppKit
import SwiftUI

/// Which screen the popover is showing. Owned by `ContentView`, driven by the
/// footer gear button and handed to `SettingsView` as a binding.
enum Route {
    case main
    case settings
}

/// Formats `Date` -> `yyyy-MM-dd` day key, so the header can fall back to the
/// current date before the first load lands.
private let dayKeyFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

private let updatedTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "h:mm a"
    return f
}()

private let defaultDBPathHint = "~/.local/share/screentime/screentime.db"

struct ContentView: View {
    @EnvironmentObject var store: ScreenTimeStore
    @State private var route: Route = .main

    /// The report shown in the top card: the browsed day if still present in the
    /// current week, otherwise today (covers a selection that fell out of the
    /// 7-day window after a date rollover).
    private var displayedReport: DayReport? {
        if let sel = store.selectedDay {
            return store.week.first { $0.day == sel } ?? store.today
        }
        return store.today
    }

    /// True only while browsing a day other than today.
    private var isBrowsingPast: Bool {
        guard let sel = store.selectedDay else { return false }
        return sel != store.today?.day
    }

    var body: some View {
        Group {
            switch route {
            case .settings:
                SettingsView(route: $route)
            case .main:
                mainBody
            }
        }
        .frame(width: 300)
        .onAppear {
            if store.today == nil { store.reload() }
        }
    }

    // MARK: - Main screen

    private var mainBody: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let msg = failureMessage, store.today == nil {
                errorView(msg)
            } else {
                if let msg = failureMessage {
                    errorBanner(msg)
                }
                ScrollView {
                    VStack(spacing: 0) {
                        if let report = displayedReport {
                            TodayCard(report: report)
                        } else {
                            loadingCard
                        }
                        Divider()
                        WeekCard(
                            week: store.week,
                            selectedDay: store.selectedDay,
                            onSelectDay: { store.selectedDay = $0 }
                        )
                    }
                }
                .frame(maxHeight: 520)
            }

            Divider()
            footer
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Screen Time")
                .font(.headline)
            Spacer(minLength: 8)
            if isBrowsingPast {
                Button { store.selectedDay = nil } label: {
                    Label("Today", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.tint)
                .help("Back to today")
            }
            Text(longDate(displayedReport?.day ?? dayKeyFormatter.string(from: Date())))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let updated = store.lastUpdated {
                Text("Updated \(updatedTimeFormatter.string(from: updated))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button { route = .settings } label: {
                Image(systemName: "gearshape")
            }
            .help("Edit app weights")
            Button { store.reload() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh now")
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .help("Quit ScreenTimeBar")
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var loadingCard: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Reading screen time…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 24)
    }

    // MARK: - Failure presentation

    private var failureMessage: String? {
        if case .failed(let msg) = store.phase { return msg }
        return nil
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
            Text(msg)
                .lineLimit(2)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.red)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.12))
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "externaldrive.badge.xmark")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(msg)
                .font(.callout.bold())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 4) {
                Text("Point the app at the database with:")
                Text("defaults write com.local.ScreenTimeBar ScreenTimeDBPath \(defaultDBPathHint)")
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            Button("Retry") { store.reload() }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 24)
    }
}
