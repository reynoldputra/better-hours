# Better Hours

Better Hours is a calendar time tracker for macOS. Block out your time on a week or day calendar, or start a timer from the menubar and fill in the details later.

![The week calendar with a running timer](docs/screenshots/calendar-dark.png)

| Block editor | Menubar popover | Projects and tags |
|---|---|---|
| ![Editing a block: title, project, tags, date and times, notes](docs/screenshots/editor.png) | ![The menubar popover with a running timer](docs/screenshots/menubar-popover.png) | ![The projects and tags window with hours per project](docs/screenshots/projects-and-tags.png) |

## Features

- **Calendar first.** Drag on the calendar to create a block, drag it to move it, and drag its edges to resize it. Everything snaps to 5 minutes.
- **Timer in the menubar.** Start, stop, or continue your last block without opening the app. The elapsed time shows in the menubar while a timer runs.
- **Projects and tags.** Give each block a project and any number of tags. Each project has a colour and shows its hours for the week.
- **Totals at a glance.** See the total for each day, for today, and for the week.
- **Private by default.** Your data stays in a file on your Mac. There is no account and the app makes no network connections.
- **Light and dark.** The app follows your system appearance.

## Install

There is no downloadable release yet, so you build the app yourself. You need macOS 14 or later, Xcode 26, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
git clone https://github.com/reynoldputra/better-hours.git
cd better-hours
apps/mac/scripts/build-release.sh
```

The script prints the path of a zip file. Unzip it and move `Better Hours.app` to your Applications folder.

The app is not signed with an Apple developer certificate, so macOS blocks it the first time you open it. Right-click `Better Hours.app` and choose Open, then confirm. If that does not work, try to open it once, then go to System Settings, Privacy & Security, and click Open Anyway.

## Using it

**On the calendar**

| To | Do this |
|---|---|
| Create a block | Drag on empty space |
| Move a block | Drag it to another time or day |
| Resize a block | Drag its top or bottom edge |
| Edit a block | Double-click it, or select it and press Return |
| Delete a block | Select it and press Delete |

**With the timer**

Type what you are working on in the bar at the top and press Return, or click the menubar icon and press Start. Continue starts a new block with the same title, project, and tags as your last one.

**Keyboard shortcuts**

| Shortcut | Action |
|---|---|
| ⌘N | New block at the current time |
| ⌘Return | Start or stop the timer |
| ⌘T | Go to today |
| ⌘← and ⌘→ | Previous and next week or day |
| ⌘1 and ⌘2 | Week view and day view |
| ⇧⌘P | Projects and tags |
| ⌘, | Settings |

## Your data

Everything is stored in one file: `~/Library/Application Support/Better Hours/betterhours.sqlite`. Copy it to back up your data, or delete it to start over.

## Development

```sh
cd apps/mac
xcodegen generate
open BetterHours.xcodeproj
```

Run the `BetterHours` scheme in Xcode. The Xcode project is generated from `project.yml` and is not committed, so run `xcodegen generate` again after pulling changes.

To run the tests:

```sh
cd apps/mac/Packages/BetterHoursCore && swift test
cd apps/mac && xcodegen generate && xcodebuild -scheme BetterHours -destination 'platform=macOS' test
```

Launching a debug build with the `-demo` argument opens the app with sample data in a temporary database, which is how the screenshots above were made. Design documents are in `specs/`.
