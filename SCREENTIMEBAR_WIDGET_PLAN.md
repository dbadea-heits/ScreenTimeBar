# ScreenTime Menu Bar Widget — Implementation Plan

## Context

Build a native macOS **menu bar** app (`ScreenTimeBar`) that, on opening its popover, shows today's and this week's screen-time productivity, in a minimal, clean, small UI. Add a **settings** gear that lets the user change per-app productivity weights (the `scores.ini` values), with a live preview, writing them back and instantly recomputing the displayed numbers.

**Data source (decided): read the SQLite DB directly** (`~/.local/share/screentime/screentime.db`) and compute all scores in-app from `~/.config/screentime/scores.ini`. The app does **not** invoke the `screentime` CLI at runtime (no subprocess, no binary-path dependency). The CLI is used only as a test oracle during verification.

End state: a double-clickable `ScreenTimeBar.app` that lives only in the menu bar (no Dock icon), re-reads the DB every time the popover opens, renders a Today card + a 7-day Week card, and has a gear button opening an in-popover weights editor with live preview and Save.

Built from scratch in the currently-empty repo `/Users/danbadea/Documents/Projects/Personal/productivity`.

## Environment & contract (verified this session)

- Toolchain: Swift 6.3.3, Xcode 26.6, `xcodegen` at `/opt/homebrew/bin/xcodegen`, macOS 26.6.2. Build target: **macOS 14.0** — all APIs used exist there.
- **DB**: `~/.local/share/screentime/screentime.db`. Schema: `CREATE TABLE app_time(day TEXT, app TEXT, seconds INTEGER, PRIMARY KEY(day, app))` and an empty `meta(key,value)`. Rows store **only raw seconds per app per local day**; `app` values are already normalized keys (`iterm2`, `whatsapp`, `firefox`, `discord`, `slackmacgap` …) that match what the CLI exports. `day` is a local `YYYY-MM-DD` string. Written by the `screentime` daemon; open **read-only**.
- **Config**: `~/.config/screentime/scores.ini`, single `[scores]` section, lines `key = int(0..10)` where `key` is a lowercased app id (some contain spaces, e.g. `google chrome`), plus `default = 5` for unlisted apps. Comments start with `#`.
- **Scoring algorithm (verified against the CLI — we reproduce it exactly):**
  - `score(app) = scores.ini[app]` if present else `default`.
  - `totalSecs = Σ seconds`.
  - `weightedScore = totalSecs == 0 ? 0 : Σ(seconds·score)/totalSecs` (verified: 6.561 for today).
  - Partition by band: `score ≥ 7 → productive`, `4..6 → neutral`, `≤ 3 → unproductive` (verified: today productive 4570 = iterm2+chrome+mail+slack).
  - Colors follow the same bands: green ≥7, orange 4–6, red ≤3.
- "today" = current local date string; "week" = the 7 local dates ending today (older→newer), zero-filled for days absent from the DB (matches the CLI's week output, which included empty days).

## Approach

Native **AppKit** entry point (`NSStatusItem` + `NSPopover` hosting SwiftUI), NOT SwiftUI `MenuBarExtra` — the status-button action is a deterministic refresh-on-open hook, gives full control over popover size, and pairs with a URL scheme for automated verification. SQLite via the system `import SQLite3` module (no third-party dependency). Built via `xcodegen` → `xcodebuild`, ad-hoc signed and unsandboxed so it can read `~/.local`/`~/.config`.

Steps are ordered so the tree builds and runs after each. All files under `Sources/ScreenTimeBar/`.

### Step 1 — Project scaffold + runnable empty menu bar app

`project.yml` (xcodegen spec):
```yaml
name: ScreenTimeBar
options:
  bundleIdPrefix: com.local
  deploymentTarget: { macOS: "14.0" }
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "5.0"            # Swift 5 language mode: avoids Swift 6 strict-concurrency build errors
    MARKETING_VERSION: "1.0"
    CURRENT_PROJECT_VERSION: "1"
    PRODUCT_NAME: ScreenTimeBar
    CODE_SIGN_STYLE: Manual
    CODE_SIGN_IDENTITY: "-"         # ad-hoc: runs locally on Apple Silicon
    DEVELOPMENT_TEAM: ""
    ENABLE_HARDENED_RUNTIME: NO
targets:
  ScreenTimeBar:
    type: application
    platform: macOS
    sources: [Sources]
    dependencies:
      - sdk: libsqlite3.tbd          # links libsqlite3 for `import SQLite3`
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.local.ScreenTimeBar
    info:
      path: Info-generated.plist
      properties:
        LSUIElement: true            # agent app: menu-bar only, no Dock icon
        CFBundleDisplayName: Screen Time
        CFBundleShortVersionString: "1.0"
        CFBundleVersion: "1"
        LSMinimumSystemVersion: "14.0"
        CFBundleURLTypes:
          - CFBundleURLName: com.local.ScreenTimeBar
            CFBundleURLSchemes: [screentimebar]
```
(If the `sdk: libsqlite3.tbd` dependency ever fails to link, fall back to `settings.base.OTHER_LDFLAGS: "-lsqlite3"`.)

`Sources/ScreenTimeBar/main.swift` (top-level executable code; do NOT use `@main` anywhere):
```swift
import AppKit
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

`Sources/ScreenTimeBar/AppDelegate.swift` (placeholder popover here; wired to the store in Step 5):
- `final class AppDelegate: NSObject, NSApplicationDelegate`.
- `applicationDidFinishLaunching`: `NSApp.setActivationPolicy(.accessory)`; `statusItem = NSStatusBar.system.statusItem(withLength: .variableLength)`; `statusItem.button?.image = NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: "Screen Time")` (fallback `"clock"` if nil), `image?.isTemplate = true`, `button.imagePosition = .imageLeading`; `button.action = #selector(togglePopover)`, `button.target = self`.
- `popover = NSPopover()`, `popover.behavior = .transient`; `contentViewController = NSHostingController(rootView: Text("…"))` with `sizingOptions = [.preferredContentSize]`.
- `@objc func togglePopover()`: if `popover.isShown` → `performClose(nil)`; else show relative to `statusItem.button!.bounds`, edge `.minY`, then `NSApp.activate(ignoringOtherApps: true)`.

Milestone (see Verification 2–3): menu bar icon appears; clicking toggles an empty popover.

### Step 2 — Config model + scoring (pure, testable)

`Sources/ScreenTimeBar/Models.swift`:
```swift
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
```

`Sources/ScreenTimeBar/ScoresConfig.swift` — lossless INI round-trip (preserves comments/order; used for scoring AND the settings editor):
```swift
struct ScoresConfig {
    private(set) var lines: [String]        // original file, line by line
    private(set) var index: [String: Int]   // lowercased key -> line number
    private(set) var scores: [String: Int]  // parsed values incl. "default"
    var defaultScore: Int { scores["default"] ?? 5 }
    static func parse(_ text: String) -> ScoresConfig
    mutating func set(_ key: String, _ value: Int)   // value clamped 0...10
    func serialized() -> String
}
```
- `parse`: split on `\n`; track section from `[header]` lines. For lines inside `[scores]` matching `key = value` (split on first `=`; skip lines whose trimmed start is `#`/`;`/`[`): record `index[key.lowercased().trimmed]` and `scores[...] = Int(value)` clamped `0...10`. Preserve all other lines verbatim.
- `set(key,value)`: `let v = min(10, max(0, value))`. If `index[key]` exists → rewrite that line as `<textBeforeFirst'='>+ "= \(v)"` (preserves key spelling/spacing). Else ensure a `[scores]` line exists (prepend if none) and **append** `"\(key) = \(v)"` at EOF (valid — single-section file), updating `index`/`scores`.
- `serialized()`: `lines.joined(separator: "\n")` with a guaranteed trailing newline.

`Sources/ScreenTimeBar/ConfigFile.swift`:
```swift
enum ConfigFile {
    static func path() -> String       // UserDefaults "ScreenTimeConfigPath" ?? $XDG_CONFIG_HOME/screentime/scores.ini ?? ~/.config/screentime/scores.ini
    static func load() -> ScoresConfig // read UTF-8 ("" if missing) -> ScoresConfig.parse
    static func save(_ cfg: ScoresConfig) throws  // mkdir -p parent; write serialized() atomically
}
```

`Sources/ScreenTimeBar/Scorer.swift` — the reimplementation of the CLI algorithm (single place; verified in Verification 1):
```swift
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
```

### Step 3 — SQLite reader (read-only)

`Sources/ScreenTimeBar/ScreenTimeDB.swift` (`import SQLite3`):
```swift
enum ScreenTimeDB {
    static func path() -> String   // UserDefaults "ScreenTimeDBPath" ?? $XDG_DATA_HOME/screentime/screentime.db ?? ~/.local/share/screentime/screentime.db
    // Inclusive date range; returns day -> (app -> seconds). Missing days simply absent.
    static func read(from: String, to: String) throws -> [String: [String: Int]]
    enum DBError: LocalizedError { case notFound(String), open(String), query(String) }
}
```
`read` implementation:
- `let p = path()`; if `!FileManager.default.fileExists(atPath: p)` → throw `.notFound(p)` (message names `p` and the `defaults write com.local.ScreenTimeBar ScreenTimeDBPath …` override).
- `var db: OpaquePointer?`; `guard sqlite3_open_v2(p, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw .open(String(cString: sqlite3_errmsg(db))) }`; `defer { sqlite3_close(db) }`.
- Prepare `SELECT day, app, seconds FROM app_time WHERE day >= ? AND day <= ?`; bind both text params with `let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)`. Step loop: read col0 `day` (`String(cString: sqlite3_column_text(stmt,0))`), col1 `app`, col2 `seconds` (`Int(sqlite3_column_int64(stmt,2))`); accumulate `result[day, default: [:]][app] = seconds`. `sqlite3_finalize` (defer). Return `result`.
- Open→query→close per call (cheap; no shared handle across threads). Read-only + same-UID perms handle WAL/rollback safely.

### Step 4 — Store (ObservableObject)

`Sources/ScreenTimeBar/ScreenTimeStore.swift`:
```swift
@MainActor final class ScreenTimeStore: ObservableObject {
    enum Phase { case idle, loading, ready, failed(String) }
    @Published var today: DayReport?
    @Published var week: [DayReport] = []
    @Published var config: ScoresConfig?
    @Published var phase: Phase = .idle
    @Published var lastUpdated: Date?
    var onLabelChange: ((_ title: String?, _ symbol: String) -> Void)?
    private var loading = false
}
```
- `func last7Days() -> [String]`: from `Calendar.current.startOfDay(for: .now)`, produce `[t-6 … t]` formatted `yyyy-MM-dd` (`en_US_POSIX`, local tz), ascending.
- `func reload()`: if `loading` return; `loading = true`; `phase = .loading` (keep existing `today`/`week` = last-good). Snapshot `let cfg = ConfigFile.load()` and `let days = last7Days()`. `Task`:
  - `do { let rows = try await Task.detached { try ScreenTimeDB.read(from: days.first!, to: days.last!) }.value; self.config = cfg; self.week = days.map { Scorer.score(day: $0, seconds: rows[$0] ?? [:], config: cfg) }; self.today = self.week.last; self.lastUpdated = .now; self.phase = .ready }`
  - `catch { self.phase = .failed((error as? LocalizedError)?.errorDescription ?? "\(error)") }` — do **not** clear prior data.
  - `self.loading = false; self.updateLabel()`.
- `func updateLabel()`: `today` present → `onLabelChange(String(format: "%.1f", today.weightedScore), "gauge.medium")`; `.failed` with no data → `onLabelChange(nil, "exclamationmark.triangle")`; else `onLabelChange(nil, "gauge.medium")`.
- `func knownApps() -> [String]`: union of `config?.scores.keys` (minus `"default"`) and every `week[].byApp.keys`; ordered by descending total seconds seen across `week`, then remaining alphabetically by `displayName`.
- `func saveWeights(_ edits: [String:Int], default def: Int) throws`: `var cfg = config ?? ScoresConfig.parse("")`; `cfg.set("default", def)`; `for (k,v) in edits { cfg.set(k, v) }`; `try ConfigFile.save(cfg)`; `self.config = cfg`; **re-score in memory** from existing seconds: `self.week = week.map { Scorer.score(day: $0.day, seconds: $0.byApp, config: cfg) }`; `self.today = week.last`; `updateLabel()`. (No DB read needed — raw seconds unchanged.)

### Step 5 — Finalize AppDelegate wiring (refresh-on-open, label, URL scheme)

Expand `AppDelegate`:
- Hold `let store = ScreenTimeStore()`. Set `popover.contentViewController = NSHostingController(rootView: ContentView().environmentObject(store))`, `sizingOptions = [.preferredContentSize]`.
- Set `store.onLabelChange = { [weak self] title, symbol in self?.statusItem.button?.title = title ?? ""; self?.statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil).map { $0.isTemplate = true; return $0 } }`. Call `store.reload()` once at launch.
- `togglePopover()`: when opening, call `store.reload()` **before** `popover.show(...)` — refresh-on-open. (Popover shows immediately with last-good/loading content; DB read is a few ms.)
- `func application(_ application: NSApplication, open urls: [URL])`: if any URL scheme is `screentimebar` → open the popover (same path as toggle-open) and `store.reload()`. Deep-link + verification hook.

### Step 6 — Formatting helpers

`Sources/ScreenTimeBar/Formatting.swift`:
- `func fmtHM(_ secs: Int) -> String`: `h=secs/3600`, `m=(secs%3600)/60`; `"Xh Ym"`, or `"Xh"`, or `"Ym"` (`"0m"` when zero).
- `func scoreColor(_ s: Double) -> Color`: `s < 4 → .red`, `< 7 → .orange`, else `.green`. Overload `scoreColor(_ s: Int)` via `Double(s)`.
- `func displayName(_ key: String) -> String`: map `["slackmacgap":"Slack","iterm2":"iTerm","quicktimeplayerx":"QuickTime","usernotificationcenter":"Notifications","theunarchiver":"The Unarchiver","loginwindow":"Idle / Lock","ical":"Calendar","google chrome":"Chrome","brave browser":"Brave"]`; fallback = `key.prefix(1).uppercased() + key.dropFirst()`.
- `DateFormatter`s (`en_US_POSIX`): `weekdayShort(_:)` (`yyyy-MM-dd`→`EEE`, e.g. Mon), `longDate(_:)` (`→ EEE, MMM d`).

### Step 7 — Main popover UI (Today + Week)

`Sources/ScreenTimeBar/ContentView.swift` — root; `@EnvironmentObject store`; `@State route: Route = .main` (`enum Route { case main, settings }`). Fixed `.frame(width: 300)`. `VStack(spacing:0)`:
- Header: `"Screen Time"` (headline) + `Spacer()` + today's `longDate` (caption, `.secondary`).
- If `case .failed(let msg)` **and** `today == nil` → full error view: centered symbol `"externaldrive.badge.xmark"`, bold `msg`, small hint with the `defaults write … ScreenTimeDBPath …` command, and a "Retry" button (`store.reload()`). Otherwise:
  - Thin error banner (only if `phase == .failed` while data present): `exclamationmark.triangle` + short message, subtle red background.
  - `ScrollView { TodayCard(report: today); Divider(); WeekCard(week: store.week) }`.
- Footer `HStack`: last-updated `"Updated h:mm a"` (caption, `.secondary`) + `Spacer()` + gear button (`gearshape` → `route = .settings`), refresh (`arrow.clockwise` → `store.reload()`), quit (`power` → `NSApp.terminate(nil)`). Plain style, `.secondary`, caption.
- When `route == .settings` → render `SettingsView(route: $route)` in place of the main body.
- `.onAppear { if store.today == nil { store.reload() } }` safety net (primary refresh is the button action).

`Sources/ScreenTimeBar/TodayCard.swift` — `VStack(alignment:.leading, spacing:10)`, padded:
- Score row: big `String(format:"%.1f", weightedScore)` (`.system(size:34,weight:.semibold).monospacedDigit()`, `foregroundStyle(scoreColor(weightedScore))`) + `"/ 10"` (`.secondary`); trailing `"Total \(fmtHM(totalSecs))"`. Below: a `Capsule` height 6 (gray-0.15 track, filled `scoreColor` width = `weightedScore/10`).
- Split bar: horizontal stacked bar height 8, rounded; segments proportional to `productiveSecs/neutralSecs/unprodSecs` (denominator = their sum, guard >0), colored green/orange/red. Legend (caption): `●Prod fmtHM · ●Neutral fmtHM · ●Unprod fmtHM`.
- Top apps: `"Top apps"` caption; `report.topApps(limit:5)` rows — `HStack{ Circle().fill(scoreColor(score)).frame(8); Text(displayName(key)); Spacer(); Text(fmtHM(secs)).monospacedDigit().foregroundStyle(.secondary) }`.

`Sources/ScreenTimeBar/WeekCard.swift` — `import Charts`; `VStack(alignment:.leading, spacing:8)`:
- `"This week"` caption + `"Total \(fmtHM(Σ totalSecs)) · Avg \(avg)"` where `avg` = mean `weightedScore` over days with `totalSecs>0` formatted `%.1f`, else `"—"`.
- `Chart(week) { BarMark(x: .value("Day", weekdayShort(day)), y: .value("Hours", Double(totalSecs)/3600)).foregroundStyle(scoreColor(weightedScore)) }`, `.frame(height: 90)`, minimal axes; empty days render zero-height.
- Contingency: if Swift Charts renders poorly in the 300pt popover, replace with an `HStack` of 7 `Capsule`s whose heights scale to `totalSecs/maxSecs` (same colors); no other change.

### Step 8 — Settings view (edit weights, live preview, save → recompute)

`Sources/ScreenTimeBar/SettingsView.swift` — `@EnvironmentObject store`; `@Binding var route: Route`; `@State edits: [String:Int]`, `@State defaultScore: Int`, `@State filter = ""`, `@State newApp = ""`, `@State saveError: String?`. On `.onAppear`, seed `edits` from `store.config?.scores` (minus `"default"`) unioned with `store.knownApps()` (missing keys → `defaultScore`), and `defaultScore` from `store.config?.defaultScore ?? 5`.
- Header: back chevron (`chevron.left` → `route = .main`) + `"Weights"` + `Spacer()` + **live preview** `Text("Today \(String(format: "%.1f", previewWeighted()))").foregroundStyle(scoreColor(previewWeighted()))` + `"Save"` button that calls `try store.saveWeights(edits, default: defaultScore)`; on success `route = .main`; on throw set `saveError` (inline red caption, stay).
  - `func previewWeighted() -> Double`: `guard let t = store.today, t.totalSecs > 0 else { return 0 }; var num = 0; for (a,s) in t.byApp { num += s * (edits[a] ?? defaultScore) }; return Double(num)/Double(t.totalSecs)`. Recomputes in-memory as steppers change — no DB, no file.
- Optional small `TextField("Filter", text:$filter)` to filter rows by `displayName`.
- `ScrollView` (max height ~300):
  - Pinned "Default (unlisted apps)" row: `Stepper(value:$defaultScore, in:0...10)`, number colored `scoreColor(defaultScore)`.
  - One row per `store.knownApps()` filtered by `filter`: `HStack{ Circle().fill(scoreColor(edits[key] ?? defaultScore)).frame(8); Text(displayName(key)); Spacer(); Text("\(edits[key] ?? defaultScore)").monospacedDigit().foregroundStyle(scoreColor(edits[key] ?? defaultScore)); Stepper("", value: binding(for:key), in:0...10).labelsHidden() }`, where `binding(for:)` reads/writes `edits[key]` defaulting to `defaultScore`.
  - "Add app" row at bottom: `TextField("app id (lowercased)", text:$newApp)` + `+` button inserting `newApp.lowercased().trimmed` into `edits` at `defaultScore`, then clearing (no-op if empty/duplicate).

Save writes `scores.ini` losslessly and re-scores `today`/`week` in memory, so the main view's numbers, colors, and menu bar label update to the new weights; the on-disk ini also keeps the `screentime` CLI consistent and persists weights across launches.

## Critical files & anchors

- `project.yml` — `dependencies: sdk: libsqlite3.tbd`, `LSUIElement: true` (menu-bar-only), ad-hoc signing, `SWIFT_VERSION 5.0`, URL scheme `screentimebar`. Errors here block everything.
- `Sources/ScreenTimeBar/ScreenTimeDB.swift` — read-only `sqlite3_open_v2`, `app_time` range query, `SQLITE_TRANSIENT` bind idiom, DB-path resolution + `notFound` hint.
- `Sources/ScreenTimeBar/Scorer.swift` — the single reimplementation of the CLI algorithm (weighted avg + ≥7/4–6/≤3 bands); its correctness is asserted against the CLI in Verification 1.
- `Sources/ScreenTimeBar/AppDelegate.swift` — `togglePopover()` calls `store.reload()` before showing (refresh-on-open); `onLabelChange` label; `application(_:open:)` URL handler.
- `Sources/ScreenTimeBar/ScreenTimeStore.swift` — DB read off-main + score, last-good retention on failure, `saveWeights` → write ini → in-memory re-score.

## Verification

Run from repo root `/Users/danbadea/Documents/Projects/Personal/productivity`.

1. **Scoring correctness vs CLI oracle (deterministic, no GUI, most important)** — write `/tmp/verify.swift` that: opens `~/.local/share/screentime/screentime.db` read-only (`import SQLite3`), reads today's rows, parses `~/.config/screentime/scores.ini`, computes `totalSecs / weightedScore / productiveSecs / neutralSecs / unprodSecs` with the Step-2 algorithm, then runs `~/.local/bin/screentime --export today` as an oracle and prints both. Run `swift /tmp/verify.swift`. **Expected: DB-computed `total/weighted/prod/neut/unprod` equal the CLI's `total_secs/weighted_score/productive_secs/neutral_secs/unprod_secs`** (weighted within 1e-9). This proves the reimplementation matches the CLI. (`swift` auto-links the `SQLite3` module; if not, `swiftc -lsqlite3 /tmp/verify.swift && ./verify`.)
2. **Generate + build**: `xcodegen generate` (expect `ScreenTimeBar.xcodeproj`) then
   `xcodebuild -project ScreenTimeBar.xcodeproj -target ScreenTimeBar -configuration Release CONFIGURATION_BUILD_DIR="$PWD/build"` → expect `** BUILD SUCCEEDED **` and `build/ScreenTimeBar.app`.
3. **Launch + liveness**: `open ./build/ScreenTimeBar.app`; after ~2s `pgrep -x ScreenTimeBar` → non-empty PID (no crash). Menu bar shows the gauge symbol + today's score (e.g. `6.6`).
4. **Menu bar visual**: `screencapture -x /tmp/menubar.png` then read `/tmp/menubar.png` — confirm gauge + score. Best-effort: if Screen Recording permission is denied the image may be blank; note rather than treat as failure.
5. **Popover open-on-URL + visual**: `open "screentimebar://open"`, wait ~0.5s, `screencapture -x /tmp/popover.png`, read it — confirm Today card (score, split bar, top apps) and Week 7-bar chart. Same permission caveat.
6. **Settings round-trip (behavioral)**: `cp ~/.config/screentime/scores.ini /tmp/scores.bak`. Open settings (gear), change one app's weight and Default — confirm the header live preview number/color updates immediately (in-memory, no save). Save. Confirm `diff /tmp/scores.bak ~/.config/screentime/scores.ini` shows only the intended value lines (comments/order preserved) and the Today card/colors/label recomputed. Cross-check authority: `~/.local/bin/screentime --export today` `weighted_score` now equals the app's displayed score. Restore: `cp /tmp/scores.bak ~/.config/screentime/scores.ini`.

Note: menu bar/popover pixels (4–5) need a human glance or a permitted `screencapture`; steps 1–3 and 6 are fully automated proof of scoring, build, launch, and the write+recompute path.

## Assumptions & contingencies

- **DB location**: `~/.local/share/screentime/screentime.db` (verified), overridable via `ScreenTimeDBPath` UserDefaults. If absent at read time, the app shows the error view naming the override — no conversation needed.
- **Config location**: `~/.config/screentime/scores.ini` (verified), overridable via `ScreenTimeConfigPath`. If missing, `ConfigFile.load()` yields an empty config (all apps score `default 5`); `saveWeights` creates the directory + file on Save.
- **DB day is local date**: verified today's rows are under the local `YYYY-MM-DD`. If Verification 1 shows `total=0` while the CLI is nonzero, the daemon writes a different tz/day — fallback: match the CLI by using its `day` field (run `screentime --export today` once at load to get the canonical day string) instead of `Calendar.current`. (Not expected; local date matched this session.)
- **WAL locking**: read-only open with same-UID permissions reads committed data safely while the daemon writes. If `sqlite3_open_v2(READONLY)` ever errors on a WAL db, retry once with URI `file:<path>?mode=ro&immutable=1`.
- **Signing**: ad-hoc, unsandboxed, no hardened runtime — required to read `~/.local`/`~/.config`. If Gatekeeper blocks first launch, right-click→Open once; do not enable App Sandbox.
- **Week chart**: Swift Charts default; hand-rolled capsule bars fallback per Step 7 if layout misbehaves.
