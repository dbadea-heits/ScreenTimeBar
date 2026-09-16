import SwiftUI

/// Weight editor. Every change lives in `edits` / `defaultScore` until "Save",
/// so the header preview recomputes purely in memory — no DB read, no file write.
struct SettingsView: View {
    @EnvironmentObject var store: ScreenTimeStore
    @Binding var route: Route

    @State private var edits: [String: Int] = [:]
    @State private var defaultScore: Int = 5
    @State private var filter = ""
    @State private var newApp = ""
    @State private var saveError: String?
    @State private var seeded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("Filter", text: $filter)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    defaultRow
                    Divider()
                    ForEach(displayedKeys, id: \.self) { key in
                        appRow(key)
                    }
                    Divider()
                    addAppRow
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 300)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 300)
        .onAppear(perform: seedIfNeeded)
    }

    // MARK: - Header

    private var header: some View {
        let preview = previewWeighted()
        return HStack(spacing: 6) {
            Button {
                route = .main
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .help("Back")

            Text("Weights")
                .font(.headline)

            Spacer()

            Text("Today \(String(format: "%.1f", preview))")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(scoreColor(preview))

            Button("Save", action: save)
                .controlSize(.small)
        }
    }

    // MARK: - Rows

    private var defaultRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(scoreColor(defaultScore))
                .frame(width: 8, height: 8)
            Text("Default (unlisted apps)")
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Text("\(defaultScore)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(scoreColor(defaultScore))
            Stepper("", value: $defaultScore, in: 0...10)
                .labelsHidden()
        }
    }

    private func appRow(_ key: String) -> some View {
        let score = edits[key] ?? defaultScore
        return HStack(spacing: 6) {
            Circle()
                .fill(scoreColor(score))
                .frame(width: 8, height: 8)
            Text(displayName(key))
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Text("\(score)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(scoreColor(score))
            Stepper("", value: binding(for: key), in: 0...10)
                .labelsHidden()
        }
    }

    private var addAppRow: some View {
        HStack(spacing: 6) {
            TextField("app id (lowercased)", text: $newApp)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onSubmit(addApp)
            Button {
                addApp()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .help("Add app")
        }
    }

    // MARK: - Data

    /// `knownApps()` order (busiest first) keeps the useful rows on top; anything
    /// only present in `edits` — e.g. an app just added by hand — follows
    /// alphabetically so it shows up immediately.
    private var displayedKeys: [String] {
        let known = store.knownApps()
        var seen = Set(known)
        let extras = edits.keys
            .filter { !seen.contains($0) }
            .sorted { displayName($0).localizedCaseInsensitiveCompare(displayName($1)) == .orderedAscending }
        seen.formUnion(extras)

        let keys = known + extras
        let needle = filter.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return keys }
        return keys.filter { displayName($0).localizedCaseInsensitiveContains(needle) }
    }

    private func binding(for key: String) -> Binding<Int> {
        Binding(
            get: { edits[key] ?? defaultScore },
            set: { edits[key] = $0 }
        )
    }

    /// Weighted average of today's seconds under the *pending* weights.
    private func previewWeighted() -> Double {
        guard let t = store.today, t.totalSecs > 0 else { return 0 }
        var num = 0
        for (app, secs) in t.byApp {
            num += secs * (edits[app] ?? defaultScore)
        }
        return Double(num) / Double(t.totalSecs)
    }

    // MARK: - Actions

    private func seedIfNeeded() {
        guard !seeded else { return }
        seeded = true

        let def = store.config?.defaultScore ?? 5
        defaultScore = def

        var seed: [String: Int] = [:]
        if let scores = store.config?.scores {
            for (key, value) in scores where key != "default" {
                seed[key] = value
            }
        }
        for app in store.knownApps() where seed[app] == nil {
            seed[app] = def
        }
        edits = seed
    }

    private func addApp() {
        let key = newApp.lowercased().trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, key != "default", edits[key] == nil else { return }
        edits[key] = defaultScore
        newApp = ""
    }

    private func save() {
        do {
            try store.saveWeights(edits, default: defaultScore)
            saveError = nil
            route = .main
        } catch {
            saveError = "Couldn't save weights: \(error.localizedDescription)"
        }
    }
}
