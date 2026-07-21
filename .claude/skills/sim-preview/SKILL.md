---
name: sim-preview
description: Preview a MilePace UI change by running it in the iOS Simulator with synthetic data and capturing a screenshot, without touching the working tree or reinstalling on a physical iPhone. Use this whenever a change affects something visual — a new view, a layout or styling tweak, a chart or map, an empty state, an error state — and whenever the user asks "does this look right?", "can you show me?", "test this before I rebuild", "what does it look like with data?", or wants to see a screen that needs data they do not currently have (a finished run, a long history, a route). Prefer this over asking the user to rebuild on their phone, since it is faster and costs them nothing.
---

# Simulator preview with synthetic data

## Why this exists

MilePace is a running app, so most interesting screens only appear after real
GPS data exists. Checking a visual change by asking the user to rebuild on their
iPhone and go outside for a run is a slow, expensive feedback loop, and it burns
their time rather than yours.

This skill closes that loop: build a throwaway copy of the app that opens
directly on the screen in question, hand it fabricated data that would otherwise
require a real run, and screenshot it. You get to actually look at the result
instead of inferring from a successful compile that it probably renders fine.

A green build says the code type-checks. It says nothing about whether the route
is framed sensibly, whether text is legible on a dark map, or whether a pause
draws a phantom line. Look at the pixels.

## The one rule that matters

**Never patch the real working tree.** The probe needs code that must never ship
— a fake entry point, synthetic records. Do all of it in a copy under the
scratchpad directory, so the user's tree stays exactly as they left it and there
is no chance of committing debug scaffolding.

Copy the app sources and the `.xcodeproj`; nothing else is needed.

## Workflow

### 1. Copy the app to scratch

```sh
SP=<scratchpad>/probe
rm -rf "$SP" && mkdir -p "$SP"
cp -R "<project>/MilePace" "<project>/MilePace.xcodeproj" "$SP/"
```

### 2. Patch the copy to open on the target screen

The app normally opens on the start screen and requires a full run to reach a
summary. Short-circuit that: replace the phase switch in `ContentView.body` with
a direct call to the view under test.

```swift
// Replace the `switch tracker.phase { ... }` block with:
ScrollView { RunDetailView(record: .probeRun).padding(20) }
```

Then append a synthetic record. Views in `ContentView.swift` are `private`, so
the fixture has to live in that same file to reach them.

Use `python3` for this rather than hand-editing — the replacement is exact,
repeatable, and asserts when the anchor text has moved, which is how you find
out the file changed underneath you instead of silently probing stale code.

### 3. Design the fixture to expose bugs, not flatter the code

A fixture that only shows the happy path wastes the run. Build in the specific
conditions that would break the feature, so the screenshot answers a real
question.

For a route map, that meant a *deliberate gap in the middle of the route with a
segment change across it* — if pause handling were broken, the screenshot would
show a straight line cutting across the map, which is exactly the bug worth
catching and is invisible to a compiler.

Also worth fabricating: a route that doubles back on itself, a single-point
route, an empty history, a very long split list, a run so short the map would
zoom to absurd detail. Ask what would look wrong, then build that.

Keep values realistic — plausible coordinates, distances, and paces — so the
screenshot reads like the real app rather than obvious test junk.

### 4. Build, run, capture

```sh
.claude/skills/sim-preview/scripts/sim_preview.sh \
  --dir "$SP" --bundle com.misery.MilePace --out "$SP/../preview.png"
```

The script builds, boots the simulator, installs, launches, waits, and captures.
Options: `--sim`, `--scheme`, `--settle`, `--out`.

### 5. Actually look at it

Read the PNG. Check what you set out to check, then look for what you did not
plan for — clipping, unreadable contrast, overlapping elements, bad framing.

The loop-route preview passed everything it was designed to test and still
surfaced a real flaw on inspection: start and finish markers landing on top of
each other, since a loop ends where it began. Nothing in the plan would have
caught it.

### 6. Confirm the tree is clean, then shut down

```sh
git -C "<project>" status -sb          # expect no unexpected modifications
grep -c "probeRun" "<project>/MilePace/ContentView.swift"   # expect 0
xcrun simctl shutdown <udid>
```

## Gotchas

These all cost real time to discover.

**`simctl` is missing without `DEVELOPER_DIR`.** If the shell resolves `xcrun` to
CommandLineTools, every `simctl` call fails with "unable to find utility". Export
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. The script does this
for you; do it yourself for any ad-hoc `simctl` command.

**Network-backed content renders blank at first.** The first map screenshot came
back as an empty grey grid, which looks exactly like a broken view. Tiles simply
had not downloaded. Twenty-five seconds later the streets appeared. Before
concluding something is broken, wait and capture again — the default `--settle`
already accounts for this.

**Top-level Swift code only runs in a file named `main.swift`.** Verification
scripts fail with "expressions are not allowed at the top level" under any other
name. Applies to standalone `swiftc` checks, not to the app itself.

**`xcodebuild` needs a concrete destination to install.** Use
`-destination 'platform=iOS Simulator,name=iPhone 17 Pro'`. The
`generic/platform=iOS Simulator` form used for compile checks produces no
installable artifact.

**First boot is slow.** Two minutes is normal. `simctl bootstatus -b` blocks
until ready rather than guessing; leave the simulator booted between iterations.

**The bundle identifier is `com.misery.MilePace`.** It was `com.example.MilePace`
before; if `launch` reports the app is not installed, check the identifier
actually built.

## When not to use this

This proves rendering, not behavior in the world. It cannot judge GPS accuracy,
real-world noise, background tracking under a locked screen, battery cost, or
haptics. Those need a physical device and a real run — say so plainly rather
than implying a simulator screenshot settled them.

It is also overkill for pure logic changes. Prefer a `swiftc` check against
`Models.swift` / `RunAccumulator.swift` when the question is arithmetic or
decoding rather than appearance.
