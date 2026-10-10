# Better Hours — Phase 1: Mac app, local only

Date: 2026-10-10
Status: draft, awaiting review
Parent: `2026-10-10-better-hours-design.md` (sections 2, 5, 6, 7, 10)

## 1. Outcome

A native macOS app that tracks time on one Mac with no account and no network. It has a main window with a week and day calendar, a menubar item with a popover, projects and tags, and light and dark themes.

Phase 1 is done when all of these hold with the network switched off:

- You can create, move, resize, edit, and delete blocks on the calendar for a full week.
- You can start, stop, continue, and start new from both the main window and the menubar popover, and the two always agree.
- The menubar shows the running block's elapsed time and keeps ticking with the main window closed.
- Quitting and relaunching loses nothing, including a running timer.
- The app follows the system light or dark appearance and matches the "App design" page of the design canvas.
- `swift test` passes for the core package, including every fixture in `fixtures/`.

## 2. Scope

In scope: everything in the parent spec's section 3 that does not involve the website, login, linking, or sync, plus a small Settings window and a release build.

Out of scope for phase 1: the sync engine and the "Connect to website" settings, undo and redo, search, block templates, recurring blocks, import and export, localisation (English only), an onboarding flow, an auto-updater, code signing with a paid certificate, and notarization.

The sync columns are in scope. They are written on every change and read by nothing until phase 3.

## 3. Decisions

"Parent" means the choice was already made in the parent spec. "Default" rows are my picks and are open to challenge.

| Topic | Decision | Chosen by |
|---|---|---|
| Language and UI | Swift 6, SwiftUI, AppKit only where SwiftUI falls short | parent |
| Database | SQLite through GRDB | parent |
| Minimum macOS | 14 | parent |
| State | The Observation framework (`@Observable`), view models on the main actor | default |
| Project generation | XcodeGen from a checked-in `project.yml`; the `.xcodeproj` is not committed | default |
| Code layout | A Swift package for all logic, a thin app target for views | default |
| Menubar | SwiftUI `MenuBarExtra` with the window style; fall back to `NSStatusItem` and `NSPopover` if it cannot do what section 9 needs | default |
| App type | A regular app with a Dock icon; closing the main window keeps it running | default |
| Sandbox | Off; the app is not distributed through the App Store | default |
| Time storage | Integer milliseconds since the Unix epoch, UTC | default |
| Project colour storage | A palette key such as `blue`, not a hex value, so each theme maps it to its own colours | default |
| Week start and clock format | Follow the system settings | default |
| Snap | 5 minutes for drag, move, and resize; minimum block length 5 minutes | parent |
| Delete | Soft delete: set `deletedAt`, keep the row | parent |
| Launch at login | A Settings toggle, off by default | default |
| Signing | Ad-hoc signing only, which is free and is what Apple Silicon needs to run a local build | default |

## 4. Repository layout

```
better-hours/
  apps/mac/
    project.yml                      XcodeGen definition
    BetterHours/                     app target
      BetterHoursApp.swift           scenes: main window, menubar, settings
      Models/                        view models
      Views/Calendar/                week grid, day column, block view, drag layer
      Views/Editor/                  block editor popover, project and tag pickers
      Views/Timer/                   timer bar, menubar popover, menubar label
      Views/Library/                 projects and tags window
      Views/Settings/
      Theme/                         colour, type, spacing, and radius tokens
      Resources/Assets.xcassets      colours with light and dark values, app icon, menubar glyph
    Packages/BetterHoursCore/        Swift package, no UI imports
      Sources/BetterHoursCore/
        Entities.swift               TimeBlock, Project, Tag, TimerSeed, PaletteColor
        LocalStore.swift
        Migrations.swift
        Totals.swift
        OverlapLayout.swift
        Snap.swift
        UUIDv7.swift
      Tests/BetterHoursCoreTests/
  fixtures/                          JSON cases shared with the TypeScript side in phase 2
  specs/
```

Everything that can be tested without a window lives in `BetterHoursCore`. The app target holds views, view models, and resources only. This keeps the logic runnable with `swift test` and makes the fixtures usable from a plain test target.

## 5. Database

The file is `~/Library/Application Support/Better Hours/betterhours.sqlite`, opened with a GRDB `DatabasePool`. Tests use an in-memory `DatabaseQueue`.

```sql
CREATE TABLE project (
  id          TEXT PRIMARY KEY,               -- UUIDv7, lowercase
  name        TEXT NOT NULL,
  color       TEXT NOT NULL,                  -- palette key
  updated_at  INTEGER NOT NULL,               -- ms since epoch, UTC
  deleted_at  INTEGER,
  dirty       INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE tag (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  updated_at  INTEGER NOT NULL,
  deleted_at  INTEGER,
  dirty       INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE time_block (
  id          TEXT PRIMARY KEY,
  title       TEXT NOT NULL DEFAULT '',
  notes       TEXT NOT NULL DEFAULT '',
  project_id  TEXT,                           -- no foreign key: the project may be soft-deleted or not yet pulled
  tag_ids     TEXT NOT NULL DEFAULT '[]',     -- JSON array of tag ids
  start_at    INTEGER NOT NULL,
  end_at      INTEGER,                        -- NULL means running
  updated_at  INTEGER NOT NULL,
  deleted_at  INTEGER,
  dirty       INTEGER NOT NULL DEFAULT 1,
  CHECK (end_at IS NULL OR end_at > start_at)
);

CREATE INDEX time_block_start ON time_block (start_at);
CREATE UNIQUE INDEX time_block_one_running ON time_block ((1)) WHERE end_at IS NULL AND deleted_at IS NULL;

CREATE TABLE sync_state (
  id              INTEGER PRIMARY KEY CHECK (id = 1),
  server_url      TEXT,
  cursor          TEXT,
  last_synced_at  INTEGER
);
```

- The two rules from the parent spec are enforced by the database itself: the `CHECK` covers `endAt` after `startAt`, and the partial unique index allows at most one running block.
- Migrations run through GRDB's `DatabaseMigrator` at launch. Phase 1 has one migration, `v1`.
- "Blocks in a range" is `start_at < :to AND (end_at IS NULL OR end_at > :from) AND deleted_at IS NULL`.
- Foundation's `UUID()` produces version 4 ids, so `UUIDv7.swift` is a small generator: 48 bits of millisecond time followed by random bits.

## 6. Core types and store

```swift
public struct TimeBlock: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var projectId: UUID?
    public var tagIds: [UUID]
    public var startAt: Date
    public var endAt: Date?          // nil means running
}

public struct Project: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var color: PaletteColor   // blue, orange, purple, pink, teal, yellow, red, gray
}

public struct Tag: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
}

public struct TimerSeed: Equatable, Sendable {
    public var title: String
    public var projectId: UUID?
    public var tagIds: [UUID]
}
```

`updatedAt`, `deletedAt`, and `dirty` are not on these types. The store owns them, so no caller can forget to set them.

```swift
public final class LocalStore: Sendable {
    public init(path: URL) throws
    public static func inMemory() throws -> LocalStore

    public func blocks(in range: DateInterval) async throws -> [TimeBlock]
    public func runningBlock() async throws -> TimeBlock?
    public func lastEndedBlock() async throws -> TimeBlock?
    public func save(_ block: TimeBlock) async throws
    public func deleteBlock(id: UUID) async throws

    public func startTimer(seed: TimerSeed?, now: Date) async throws -> TimeBlock
    public func stopTimer(now: Date) async throws -> TimeBlock?

    public func projects() async throws -> [Project]
    public func save(_ project: Project) async throws
    public func deleteProject(id: UUID) async throws

    public func tags() async throws -> [Tag]
    public func save(_ tag: Tag) async throws
    public func deleteTag(id: UUID) async throws

    public func changes() -> AsyncStream<Void>
}
```

- **`changes()` is a method, not a property.** An `AsyncStream` has a single consumer, and the main window, the menubar, and the library window each need their own. Each call returns a fresh stream. The parent spec showed a property; this corrects it.
- **`now` is a parameter on the timer methods** so tests control the clock. Both methods read it; nothing else needs it.
- **`startTimer` and `stopTimer` are single transactions.** `startTimer` ends any running block at `now` and inserts the new one in the same write, so the unique index is never violated.
- **`save` is create-or-update by id.** It sets `updated_at` to the current time and `dirty` to 1.
- **Deletes are soft.** List methods never return soft-deleted rows.
- **`lastEndedBlock`** is what "Continue" and the idle popover read: the non-deleted block with the latest `end_at`.

Pure functions, also in the core package:

```swift
public func total(of blocks: [TimeBlock], in interval: DateInterval, now: Date) -> TimeInterval
public func layoutColumns(for blocks: [TimeBlock], now: Date) -> [UUID: ColumnSlot]   // index and count for side-by-side overlap
public func snap(_ date: Date, toMinutes step: Int, calendar: Calendar) -> Date
```

`total` clips each block to the interval and counts a running block up to `now`. Day, week, and per-project totals are all this one function with different inputs.

## 7. App structure

Three scenes in `BetterHoursApp`:

- `Window("Better Hours", id: "main")` for the calendar.
- `MenuBarExtra` with the window style for the popover.
- `Settings` for the settings window. Projects and tags open as a second `Window` from the toolbar button.

One `LocalStore` is created at launch and injected into three view models, all `@Observable` and `@MainActor`:

| Model | Owns | Used by |
|---|---|---|
| `TimerModel` | The running block, the last ended block, today's and this week's totals, and the start, stop, continue, and new actions | Timer bar, menubar label, popover |
| `CalendarModel` | The visible range and view mode, the blocks in range, the selection, and the in-progress drag | Calendar grid, block editor |
| `LibraryModel` | Projects and tags | Editor pickers, projects and tags window, block colours |

Each model reloads from the store when `changes()` fires. No view talks to the store directly, and no model talks to another model.

**Ticking.** Elapsed time and the "now" line are derived from the running block's `startAt` and the current time; nothing is written to the database while a timer runs. Views that show a live value use `TimelineView` with a one-second schedule, and only while a block is running.

**Window behaviour.** Closing the main window hides it and the app keeps running. Clicking the Dock icon or "Open Better Hours" in the popover brings it back. Quit is in the app menu and the popover.

## 8. Calendar

The grid is custom SwiftUI. It is the largest piece of phase 1.

**Layout**

- A 56-point time gutter and seven day columns in week view, one in day view.
- All 24 hours in a vertical scroll view at 56 points per hour. On open, it scrolls so the current time is in view, or 08:00 when the visible week does not contain today.
- A header row with the day name, date, and that day's total. Today's column is tinted with the accent colour.
- Blocks are positioned from their start and end in local time. A block that crosses midnight is drawn as two pieces, one in each day.
- Overlapping blocks share the column width using `layoutColumns`.
- A block shorter than 30 minutes shows its title only, on one line.

**Interactions**

| Gesture | Result |
|---|---|
| Drag on empty space | A dashed ghost follows the pointer; releasing creates the block and opens the editor with the title focused |
| Drag a block | Moves it, within the day or to another day in week view |
| Drag a block's top or bottom edge | Resizes it; a grip appears on hover |
| Click a block | Selects it |
| Double-click, or Return on a selected block | Opens the editor |
| Delete on a selected block | Deletes it |
| Click empty space, or Escape | Clears the selection |

All drags snap to 5 minutes and cannot make a block shorter than 5 minutes. During a drag the block shows the times it would get. The store is written once, on release.

The running block can be edited and its start moved, but its end cannot be dragged; the end is always "now" until the timer stops.

**Keyboard**

| Keys | Action |
|---|---|
| ⌘T | Go to today |
| ⌘← and ⌘→ | Previous and next week, or day |
| ⌘1 and ⌘2 | Week view and day view |
| ⌘N | New block at the current time, one hour long, editor open |
| ⌘Return | Start the timer, or stop it if running |

**Editor.** A popover anchored to the block, with the fields on the design canvas. Save writes once; Cancel and Escape discard. Delete asks for a second click in place. Start and end are typed as times with a date; an end at or before the start shows the field error "End must be after start" and disables Save.

**Pickers.** The project picker is a menu of projects with their colour dots, plus "No project". The tag picker is a text field with suggestions; typing a name that does not exist offers to create it.

## 9. Timer bar and menubar

**Timer bar** (main window): a title field, the project, the elapsed time, and one button. Idle shows a placeholder and Start; running shows the title and Stop. Typing a title and pressing Return while idle starts a timer with that title. Editing the title while running renames the running block when focus leaves the field.

**Menubar label:** the glyph alone when idle; the glyph and elapsed time as `h:mm` when running. The glyph is a template image so macOS tints it for light and dark menubars.

**Popover:** as drawn on the canvas. Running shows the title field, project, elapsed time with seconds, and Stop. Idle shows the last block with Continue and New; with no blocks at all it shows only "Start". Below that, today's total, "Open Better Hours" (⌘O), and Quit (⌘Q).

Both surfaces call the same `TimerModel`, so they cannot disagree.

**To verify in a spike before building on it:** that `MenuBarExtra` can show a label whose text changes every minute, and that its window-style popover sizes and dismisses the way the design expects. If either fails, the menubar moves to `NSStatusItem` with an `NSPopover` hosting the same SwiftUI view; nothing else in this spec changes.

## 10. Projects, tags, and settings

**Projects and tags window:** as drawn on the canvas. A project has a name and one of the eight palette colours. Each row shows the project's hours for the current week. Rename is inline; delete asks for a second click.

Deleting a project or tag is a soft delete. Blocks that referenced it keep the id and simply show without it, as the parent spec requires.

**Settings window:** one toggle, "Launch at login", using `SMAppService`. Phase 3 adds the sync section here.

## 11. Theme

Tokens come from the "Brand" page of the canvas and are defined once in `Theme/`:

- **Colours** are named colour sets in the asset catalog, each with a light and a dark value: background, surface, sunken, line, text, muted text, accent, accent soft, danger, and a fill and an ink colour for each of the eight project colours.
- **Type** is the system font: SF Pro for interface text and SF Mono for timers and durations, at the sizes on the canvas.
- **Spacing** uses the 4-point scale; **corner radii** are 4 for blocks, 6 for controls, 10 for panels, and full for tags.
- **Control height** is 32 points, as on the "App design" page.

The app follows the system appearance. There is no in-app theme switch in phase 1.

**App icon and glyph:** generated from the mark on the canvas into the asset catalog sizes macOS needs.

## 12. Interaction baseline

Every screen has to behave like a Mac app, not only look like the design. This is a requirement of each build step, not a polish pass at the end.

- **System chrome first.** The main window uses the real window toolbar (unified style) for navigation, the range title, the Week/Day switch, and the projects and tags button. The system then owns the spacing beside the window buttons, window dragging, double-click to zoom on the toolbar only, and toolbar button states. The app does not hide the title bar or draw its own.
- **System controls first.** Buttons, pickers, text fields, menus, and alerts are the standard controls, tinted with the theme's accent. A custom-drawn control is used only where no system control fits: time blocks, tags, and the calendar grid.
- **States on every custom element.** Each one has hover, pressed, selected, keyboard-focus, and disabled appearances where they apply, as drawn on the canvas's component states sheet.
- **Pointer.** Buttons keep the arrow pointer, as on macOS generally. Block edges show the resize pointer, text fields the I-beam, and a block being dragged the closed hand.
- **Tooltips and labels.** Every icon-only control has a tooltip and an accessibility label.
- **Verification.** A step is not done on snapshots alone. Each step's report lists the interactions that were tried in the running app and the ones nobody has seen.

## 12a. Empty and edge states

- **First launch:** an empty week, the timer bar idle, and one line of hint text in the grid: "Drag on the calendar to block time, or press Start."
- **No projects:** the project picker shows "No project" and "New project…".
- **Running timer at launch:** the block is still running; elapsed time is computed from its start, so time while the app was closed counts.
- **Running timer across midnight:** drawn as two pieces; each day's total counts its own part.
- **Clock changes:** on daylight-saving days the grid still shows 24 rows, so blocks near the change are drawn up to an hour off. Stored times and totals are correct. This is accepted for phase 1.
- **Database error:** a blocking alert with the error text; the app does not continue with unsaved state.

## 13. Testing

**Core package, automated (`swift test`):**

- `LocalStore` against an in-memory database: create, update, soft delete, range queries including blocks that straddle the range edges, the dirty flag and `updatedAt` on every write, start and stop, starting while running, `lastEndedBlock`, and a `changes()` event per write to every subscriber.
- The database rules: a second running block is rejected by the index, and an end before the start is rejected by the check.
- Fixtures: `fixtures/totals.json`, `fixtures/overlap-layout.json`, and `fixtures/snap.json`. Each case is an input and an expected output; the Swift tests load and assert every case.

**View models, automated:** `TimerModel` and `CalendarModel` against an in-memory store with an injected clock: totals update after a write, continue seeds from the last block, a drag commits one write.

**Manual checklist:** every row of section 8's gesture and keyboard tables; the menubar ticking with the main window closed; popover open and close; light and dark appearance; quit and relaunch with a running timer; launch at login.

## 14. Build order

Each step ends with something that runs and a check that proves it.

| Step | Work | Check |
|---|---|---|
| 1 | Repository skeleton, `project.yml`, core package, entities, UUIDv7, migration `v1`, `LocalStore` | `swift test` passes the store and database-rule tests |
| 2 | `total`, `layoutColumns`, `snap`, and the three fixture files | `swift test` passes every fixture case |
| 3 | App target, theme tokens, read-only week and day grid from the store, navigation, day totals | A database seeded by hand shows the week from the canvas, in both appearances |
| 4 | Drag to create, move, resize, selection, the editor, pickers, delete | Section 8's gesture table passes by hand |
| 5 | `TimerModel`, timer bar, menubar label and popover, the `MenuBarExtra` spike | Start in the popover and stop in the window; the two stay in step with the window closed |
| 6 | Projects and tags window, settings, empty states, keyboard shortcuts, app icon, release build | The section 1 checklist passes on a clean user account |

Steps 1 and 2 have no UI and no unknowns. Step 4 is the largest and the most likely to need AppKit for the drag layer. Step 5 carries the one spike.

**Release build:** `xcodegen` then `xcodebuild` in Release configuration with ad-hoc signing, zipped and attached to a GitHub release. The README explains the Gatekeeper prompt on first launch.

## 15. Open questions

- **Undo.** Mac users expect ⌘Z after a mistaken drag or delete. I left it out to keep phase 1 small; adding it later means routing writes through an undo manager.
- **Dock icon.** A menubar-only app with no Dock icon is the alternative. I kept the Dock icon because the main window is the primary surface.
- **XcodeGen.** It adds a tool to the build. The alternative is committing the `.xcodeproj`, which is harder to review and to edit by hand.
- **Day range.** The grid shows all 24 hours and scrolls. A setting for working hours is the alternative.
