# ScreenTimeBar — Click a week bar to load that day

## Context

Today the popover shows a fixed "Today" card (`store.today`) above a 7‑day `WeekCard` bar chart that is display‑only. Requested change: clicking a bar in the week chart makes the top card show **that** day's report (score, split bar, top apps) and updates the header date, with a way to return to today. The menu‑bar label must keep showing the real current day. All data already exists in `store.week` (7 `DayReport`s, oldest→newest); this is a view‑selection feature, no new DB/scoring work.

End state: tap any week bar → top card + header switch to that day and the tapped bar is highlighted; a "Today" control returns to the current day; reopening the popover or hitting Refresh returns to today.

## Approach

Selection is a single day‑string key (`"yyyy-MM-dd"`) held in the store, so it survives the in‑memory re‑score in `saveWeights` and the array replacement in `reload()` by lookup, and so the popover‑open path (`AppDelegate.showPopover` → `store.reload()`) can reset it deterministically without depending on SwiftUI `onAppear` timing.

### 1. Store: add selected‑day state, reset on every load

`Sources/ScreenTimeBar/ScreenTimeStore.swift`.

- Add published state next to the other display state (after line 17, `@Published var lastUpdated: Date?`):
  ```swift
  /// Day the user is browsing in the popover ("yyyy-MM-dd"), or nil for today.
  /// View-only: the status-item label always reflects `today`, never this.
  @Published var selectedDay: String?
  ```
- In `reload()` (line 47), make the **first statement of the method body** (before the `if loading { return }` guard) reset it, so every popover open and every manual Refresh returns to today:
  ```swift
  func reload() {
      selectedDay = nil
      if loading { return }
      ...
  ```
- Do **not** touch `saveWeights` (line 125) or `updateLabel` (line 82): re‑scoring keeps the same day keys so the browsed day updates in place, and the label intentionally stays bound to `today`.

### 2. WeekCard: key bars by day, highlight the shown day, tap to select

`Sources/ScreenTimeBar/WeekCard.swift`. Add two stored properties and rework `chart` only; `totalSecs`, `avgText`, and `body` (the header row + `if week.isEmpty` guard) are unchanged.

- New stored properties on the struct (after `let week: [DayReport]`, line 5):
  ```swift
  let selectedDay: String?
  let onSelectDay: (String) -> Void
  ```
- New computed helper — the day whose bar is drawn "active". `store.today == week.last`, so a nil selection highlights today:
  ```swift
  private var highlightedDay: String? { selectedDay ?? week.last?.day }
  ```
- Rewrite `chart` (lines 45–67). Three changes plus a tap overlay:
  - **Key the x‑value by the day string** (was `weekdayShort(day.day)`) so `proxy.value(atX:)` returns the day key directly and highlight compares keys:
    ```swift
    BarMark(
        x: .value("Day", day.day),
        y: .value("Hours", Double(day.totalSecs) / 3600)
    )
    .foregroundStyle(scoreColor(day.weightedScore).opacity(day.day == highlightedDay ? 1 : 0.4))
    ```
  - **Restore the weekday axis labels** (raw key is `2026-09-14`; map it to `Mon`) by replacing the `.chartXAxis` block:
    ```swift
    .chartXAxis {
        AxisMarks { value in
            AxisValueLabel {
                if let d = value.as(String.self) {
                    Text(weekdayShort(d))
                }
            }
        }
    }
    ```
  - Keep `.chartLegend(.hidden)`, the existing `.chartYAxis` block, `.font(.caption2)`, `.frame(height: 90)` exactly as they are.
  - **Append a tap overlay** after `.frame(height: 90)`. macOS 14 has no `.chartGesture` (that is macOS 15+), so use `.chartOverlay` + `SpatialTapGesture` (macOS 13+) + `ChartProxy.plotFrame` (macOS 14+) + `value(atX:as:)`. The `value(atX:)` result drives selection; the index‑math branch is a fallback only if the band scale returns nil at inter‑bar padding:
    ```swift
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
    ```

  No‑data path is already handled: `body` renders the chart only in the `else` of `if week.isEmpty`, so there is no overlay when there are no bars. Tapping a zero‑height (empty) day still resolves its band to that day key and shows a zeroed card, which `TodayCard` already renders safely.

### 3. ContentView: show the selected day, header date + Today reset, wire the callback

`Sources/ScreenTimeBar/ContentView.swift`.

- Add two computed properties on `ContentView` (place near the top of the struct, e.g. after line 31):
  ```swift
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
  ```
- `mainBody` (lines 61–70): the top card must follow the selection. Replace the `if let today = store.today { TodayCard(report: today) }` binding with `displayedReport`, and pass the new `WeekCard` arguments:
  ```swift
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
  ```
  Leave the surrounding `if let msg = failureMessage, store.today == nil { errorView }` / `errorBanner` structure unchanged.
- `header` (lines 80–91): the date must reflect the shown day, and a "Today" reset must appear while browsing a past day. Replace the header body with:
  ```swift
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
  ```

`TodayCard` is unchanged: it already takes any `DayReport` and renders all‑zero days safely (`scoreFraction` clamps, `bandFraction` guards `bandTotal > 0`, empty `topApps` shows its placeholder). The struct keeps its name; it now renders the selected day rather than strictly today, which the header date makes clear.

## Critical files & anchors

- `Sources/ScreenTimeBar/WeekCard.swift` — `chart` (lines 45–67). The only non‑obvious work: x keyed by `day.day` with a weekday `AxisValueLabel`, opacity highlight, and the `.chartOverlay` tap. macOS 14 constraint: `.chartOverlay`+`SpatialTapGesture`, not `.chartGesture`.
- `Sources/ScreenTimeBar/ScreenTimeStore.swift` — `reload()` (line 47) resets `selectedDay` first; new `@Published var selectedDay` after line 17.
- `Sources/ScreenTimeBar/ContentView.swift` — `mainBody` (lines 61–70) and `header` (lines 80–91); new `displayedReport` / `isBrowsingPast`.

## Verification

Repo root `/Users/danbadea/Documents/Projects/Personal/productivity`. The project has no unit‑test target; verify by build + launch + interaction, matching the existing widget verification method.

1. **Build**: `xcodegen generate && xcodebuild -project ScreenTimeBar.xcodeproj -target ScreenTimeBar -configuration Release CONFIGURATION_BUILD_DIR="$PWD/build"` → `** BUILD SUCCEEDED **`, zero warnings from `Sources/*`. This catches the load‑bearing API assumptions (`proxy.plotFrame`, `value(atX:as:)`, `AxisValue.as`, `SpatialTapGesture` on macOS 14).
2. **Launch**: `pkill -x ScreenTimeBar; open ./build/ScreenTimeBar.app; sleep 2; pgrep -x ScreenTimeBar` → non‑empty PID.
3. **Day‑select interaction** (primary new behavior): `open "screentimebar://open"`; `screencapture -x /tmp/p0.png` and read it → note today's header date, big score, and the menu‑bar number. Then synthetic‑click an earlier bar in the week chart (left half of the chart row) via `osascript -e 'tell application "System Events" to click at {X, Y}'` where `{X,Y}` is a bar left of the rightmost, derived from the captured popover frame; `screencapture -x /tmp/p1.png` and read it. Expected observable change: the big top card (score, `Total`, split bar, top‑apps list) and the header date now show the **clicked weekday's** values; that bar is full‑opacity while the others dim; a `‹ Today` control appears in the header; the **menu‑bar number is unchanged** from step 3's reading.
4. **Return to today**: click the header `‹ Today` control (or press the in‑popover Refresh); `screencapture -x /tmp/p2.png` → top card + header are back to today and the `‹ Today` control is gone.
5. **Reopen resets**: click a past bar again, close the popover, reopen via `screentimebar://open` → it shows today, confirming `reload()` clears the selection.

## Assumptions & contingencies

- **Refresh/reopen return to today (default chosen).** Placing `selectedDay = nil` in `reload()` means the in‑popover Refresh button and every reopen snap back to today. If browsing should instead persist across Refresh/reopen, remove that line from `reload()` and reset only via the header `‹ Today` button.
- **`ChartProxy.value(atX:)` on the categorical band scale returns the day key.** This is the documented Apple pattern and the primary path; the index‑math branch in the overlay is the pre‑decided fallback if it returns nil at inter‑bar padding, so the implementer never needs to choose at runtime.
- **`store.today == store.week.last`.** Holds because `reload()` sets `today = week.last` and `saveWeights` sets `today = week.last`; this is why `highlightedDay` defaults to `week.last?.day` and `isBrowsingPast` compares against `store.today?.day`. No code change relies on anything stronger.
