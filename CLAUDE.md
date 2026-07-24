# MilePace Claude Code Handoff

Last updated: 2026-07-21

This file is the source-of-truth handoff for continuing MilePace with Claude Code. Read it before editing, and update it when the facts below stop being true.

## How to write responses

Write all responses to the user in ASD-STE100 Simplified Technical English. This is the AeroSpace and Defence Simplified Technical English standard. It is a controlled language. It removes ambiguity from technical writing.

Obey these rules:

- Use one word for one meaning. Do not use a word as more than one part of speech.
- Write procedural sentences with a maximum of 20 words. Write descriptive sentences with a maximum of 25 words.
- Give one instruction in one sentence.
- Use the active voice. Use the passive voice only when the agent is not important.
- Use the simple present, past, or future tense. Do not use a gerund or a participle in place of a verb.
- Keep the articles. Write "the map" and not "map".
- Do not make a noun cluster of more than three words.
- Write a maximum of six sentences in a paragraph.
- Put the most important information first.
- Do not remove words to make the text short. Short text that is not clear is a failure.

Do not apply the standard to these items:

- Code, identifiers, file paths, and commands.
- Quoted tool output and error messages.
- Commit messages and pull request text. These keep the conventions in this file.

The standard makes text clear. It does not make text abrupt. Answer the full question.

## Product intent

MilePace is a deliberately small, local-first iPhone running app. Its primary job is to let a runner glance at a stable mile pace without a Strava subscription.

Core product constraints:

- Native SwiftUI iPhone app, iOS 17+.
- Miles and minutes-per-mile are the primary units.
- No account, backend, advertising, analytics SDK, or subscription.
- Runs stay on the device unless the user explicitly shares or exports them.
- Keep the live running screen high-contrast, glanceable, and simple.
- Preserve background GPS tracking while a run is active.
- The repository is public and MIT licensed.

Public repository: <https://github.com/misery-hl/MilePace>

## Open the correct Xcode project

Open `MilePace.xcodeproj` directly. Do not open the repository folder or `Package.swift` as the main Xcode workspace. Opening the package selects the `MilePaceCore` library scheme, which builds but cannot install an app.

The Xcode toolbar should show:

```text
MilePace -> <physical iPhone or simulator>
```

not:

```text
MilePaceCore -> <device>
```

## Current Git state

`main` is clean and fully pushed. Every change so far went in through a pull
request; twelve are merged and none are open. Recent history:

```text
23df1b2 Merge pull request #12 from misery-hl/feat/yards-start-at-forty
126c4e6 Start the yard picker at 40, and step it by 10
6b1616c Merge pull request #11 from misery-hl/feat/goal-distance-units
e9aef67 Pick a goal distance in even steps, in the unit the runner thinks in
4d3f84c Merge pull request #10 from misery-hl/fix/user-story-findings
2e6cc22 Fix defects found by user-story walkthroughs
b9626f7 Merge pull request #9 from misery-hl/feat/multiple-goals
af75c87 Support several goals at once, with editing and guarded deletion
```

The signing and bundle-identifier changes that once had to be preserved in the
worktree are committed as of PR #3, with the owner's explicit approval to
publish `DEVELOPMENT_TEAM` in this public repository. There is no user-owned
uncommitted change to work around.

## Working agreement

The user wants proper source control, not direct commits to `main`:

1. Branch for every change (`feat/`, `fix/`, `chore/`).
2. Stage explicit paths. Avoid `git add -A` so unrelated Xcode churn does not ride along.
3. Show `git status -sb` and the diff before committing.
4. Open a PR with `gh`, describing the problem, the change, whether stored run data is affected, and what verification ran.
5. Merge to `main` and delete the branch.

`gh` is installed and authenticated as `misery-hl` with `repo`, `workflow`, `read:org`, and `gist` scopes.

**Verify on device before merging anything visual or GPS-dependent.** This was learned the hard way: the social share card was merged after a clean build, and the very first tap on a physical iPhone revealed the share sheet had no apps in it. The build passing means the code compiles, not that the feature works. Xcode builds from the working tree, so the user can always test a fix before it is merged — offer that instead of merging first.

## Implemented functionality

- Start, pause, resume, and finish a run.
- High-accuracy Core Location tracking with `.fitness` activity type.
- Tracking continues in the background after a run starts.
- Active time excludes explicit pauses.
- Total distance in miles.
- Current-mile projected pace after at least 30 meters.
- Rolling pace based on the recent GPS window.
- Exact mile split interpolation when a GPS segment crosses a mile boundary.
- Haptic feedback at completed miles.
- Local JSON run history in Application Support.
- Recent-run detail views with average pace and mile splits.
- **Recorded GPS route persisted per run, and a dark route map on saved runs.**
- **Goals: several at once. A goal is a run (miles or kilometres, entered as a total time or a pace per mile) or a sprint (metres or yards up to about a mile, entered as a total time only). Add, edit, and delete them, with a confirmation that states what is lost. A live projected finish for the goal being followed, and a summary comparing each added run with the target, the previous run, and the best run.**
- Post-run social share card and native iOS share sheet.
- Privacy manifest declaring no tracking or collected/transmitted data.
- 1024x1024 opaque app icon and an icon-generation utility.

## Architecture map

- `MilePace/MilePaceApp.swift`
  - Creates and injects `RunStore` and `RunTracker`.
  - Refreshes elapsed state when the app becomes active.
- `MilePace/ContentView.swift`
  - Start screen, live run dashboard, saved-run details, summary, route map, and social sharing.
- `MilePace/RunTracker.swift`
  - Core Location lifecycle, authorization, filtering, pause/resume timing, background updates, haptics, trackpoint recording, and saving finished runs.
- `MilePace/RunAccumulator.swift`
  - Pure pace and split math. Keep this independent from Core Location so it remains directly testable.
- `MilePace/Models.swift`
  - `RunRecord`, `MileSplit`, `TrackPoint`, `RouteBounds`, formatting, and the meters-per-mile constant. **Keep this free of Core Location and MapKit** — coordinates are stored as plain `Double`s specifically so `Tools/VerifyPaceEngine.swift` can compile it with bare `swiftc`.
- `MilePace/PacePrediction.swift`
  - Riegel race prediction, goal attempts, and goal comparison. **Keep this free of frameworks** for the same reason as `Models.swift`.
- `MilePace/RunStore.swift`
  - Local JSON persistence.
- `MilePace/GoalStore.swift`
  - Local JSON persistence for goals, in `goals.json`.
- `MilePaceTests/RunAccumulatorTests.swift`
  - XCTest coverage for pace and split calculations.
- `Tools/VerifyPaceEngine.swift`
  - Framework-independent executable checks for environments where XCTest is unavailable.
- `Tools/GenerateAppIcon.swift`
  - Rebuilds the app icon with Core Graphics.
- `.claude/skills/sim-preview/`
  - Skill for previewing UI changes in the iOS Simulator with synthetic data. See below.

## Route recording and the map

`RunRecord.trackPoints` stores the recorded route. Each `TrackPoint` carries latitude, longitude, timestamp, optional altitude, horizontal accuracy, and a `segment` index.

Two design points worth preserving:

- Points are only recorded for fixes that already pass the tracker's accuracy filters, so poor GPS is not drawn.
- The route is thinned by `RouteThinning` when the run is saved. Fixes arrive every 2 m, which the distance maths needs but the stored route does not. Without thinning a 150-run history reached 76.9 MB and blocked the main thread for 1.5 s on every save. Thinning keeps the first and last point of every segment, so the route still starts and ends where the runner did and a pause still reads as a gap.
- `segment` increments on **resume**. `routeSegments` groups by it so the drawn route breaks at a pause instead of connecting where the runner stopped to where they started again.

`RouteMapView` renders it: dark standard map with points of interest excluded, mint route line, start and finish markers, framed by `routeBounds` with a margin and a minimum span so a very short run does not zoom absurdly.

**Known nit:** on a loop, the start and finish markers overlap, because you finish where you began. Making them different sizes would let both read when concentric.

Runs recorded before this feature have no coordinates and show no map. That data cannot be recovered retroactively.

## Persistence compatibility

`RunRecord` has an explicit `init(from:)` that decodes `trackPoints` with `decodeIfPresent`, defaulting to empty. This is deliberate: a plain synthesized `Codable` conformance would fail on a missing key and take **the entire `runs.json` file** down with it, not just the one run.

Apply the same care to any future field. When changing this model, re-run the migration check described below rather than assuming.

## Remaining data limitation

Route coordinates are now persisted, so a route map and GPX export are both feasible. Still missing for a full activity file:

- per-point cadence or heart rate (not collected, and out of scope without external sensors);
- explicit pause/resume markers in exported output (the `segment` index carries this and should map to GPX track segments).

## Strava conclusion

The recommended first integration is GPX export plus the user-driven Strava file uploader, not a direct API dependency.

Reasons:

- Strava accepts timestamped GPX, TCX, and FIT uploads.
- Current Strava developer documentation says a subscription is required to create a new API application.
- New apps begin in single-player mode, then have a small athlete capacity before review.
- A public OAuth integration needs a backend because the client secret must not be embedded in an open-source iOS binary.
- Strava's June 2026 API policy prohibits competing with or replicating Strava functionality, creating risk for a "free premium replacement" that also uses its API.
- Apple Health is not a sync workaround: Strava currently imports only workouts recorded by Apple's native Workout app, not third-party workouts written into HealthKit.

References:

- <https://developers.strava.com/docs/uploads/>
- <https://developers.strava.com/docs/getting-started/>
- <https://developers.strava.com/docs/authentication/>
- <https://www.strava.com/legal/api_policy>
- <https://support.strava.com/en-us/articles/15402066-how-to-get-your-activities-to-strava>

Do not scrape Strava or automate its web interface.

## Verification commands

Use full Xcode explicitly:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -quiet \
  -project MilePace.xcodeproj \
  -scheme MilePace \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/MilePaceBuild \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Validate the platform-independent module and pace checks:

```sh
swift build

swiftc \
  MilePace/Models.swift \
  MilePace/RunAccumulator.swift \
  Tools/VerifyPaceEngine.swift \
  -o /private/tmp/milepace-engine-check

/private/tmp/milepace-engine-check
```

Expected output includes:

```text
Passed 5 pace-engine checks
```

Check the race prediction and goal comparison:

```sh
swiftc \
  MilePace/Models.swift \
  MilePace/PacePrediction.swift \
  Tools/VerifyGoalEngine.swift \
  -o /private/tmp/milepace-goal-check

/private/tmp/milepace-goal-check
```

Expected output includes:

```text
Passed 142 goal-engine checks
```

Also run:

```sh
git diff --check
plutil -lint \
  MilePace/Info.plist \
  MilePace/PrivacyInfo.xcprivacy \
  MilePace.xcodeproj/project.pbxproj
```

**When touching `RunRecord` or anything `Codable`,** write a throwaway check that decodes a legacy JSON payload lacking the new field and confirms old runs still load with their summary values intact. Compile it against `MilePace/Models.swift` with `swiftc`. Note that top-level Swift statements only run in a file literally named `main.swift`.

To look at a UI change, use the `sim-preview` skill rather than asking the user to rebuild on their phone.

## Previewing UI changes

`.claude/skills/sim-preview/` documents the fast visual feedback loop, with `scripts/sim_preview.sh` handling build, boot, install, launch, settle, and screenshot in one command.

The approach: copy the app to a scratch directory, patch the copy to open directly on the screen under test, hand it synthetic data, and screenshot it. **Never patch the real working tree.**

The most valuable habit it encodes: design the fixture to expose bugs rather than flatter the code. The route-map fixture deliberately contained a pause gap, so broken pause handling would have drawn a visible straight line across the map — something no compiler catches.

Read the skill for the full gotcha list. Two that waste the most time: `simctl` is missing entirely unless `DEVELOPER_DIR` points at Xcode rather than CommandLineTools, and map tiles render as a blank grey grid on cold launch and fill in seconds later, which looks exactly like a broken view.

This proves rendering only. GPS accuracy, real-world noise, background tracking, and battery still require a physical device.

## Physical-device workflow

The user builds and installs from Xcode onto a paired iPhone.

For each local update:

1. Keep `MilePace -> Clawdene's iPhone` selected in the Xcode toolbar.
2. Press Command-R to rebuild and install.
3. Keep the phone unlocked during installation.
4. Outdoor GPS behavior must be validated on the phone; the simulator is insufficient for final pace accuracy and background-lock behavior.

The bundle identifier is now `com.misery.MilePace` and should stay stable.

**Changing the bundle identifier creates a new app identity.** When it changed from `com.example.MilePace`, iOS installed a second, separate app rather than updating the first, and the run recorded in the old app stayed in the old app's container. Switching between TestFlight and Xcode builds of the *same* identifier also forces a fresh install because the signing differs, which wipes the container. Consecutive Xcode rebuilds of the same identifier update in place and preserve run history.

Because history is local-first with no backup by design, a container wipe is unrecoverable. This is a real argument for shipping an export or backup path before asking the user to accumulate runs they would miss.

## Known open defects

Five agents walked user stories through the code on 2026-07-21. Twenty of the twenty-one findings are now fixed. One remains:

1. **History still grows without bound.** Route thinning cut a 150-run history from 76.9 MB to 8.9 MB, and the encode from 1.50 s to 0.15 s, and the write now happens off the main actor. But the whole file is still rewritten on every save. At a few hundred runs this is fine. Well beyond that, move to one file per run, or an index with lazily loaded routes.

Fixed since: Reduced Accuracy and a changed device clock now raise a warning on the running screen instead of silently dropping every fix; storage read and write failures are reported instead of swallowed; an implausible target cannot be saved; and a best time derived from a scaled run is labelled as an estimate on the goal card.

## Recommended next work

Prioritize in this order unless the user changes direction:

1. Validate a real outdoor run end to end: distance, live pace stability, exact mile split, pause/resume, screen lock, battery, and how live GPS noise reads when the route is drawn. If the line looks jittery, consider light smoothing or a tighter accuracy threshold on recorded points.
2. Fix the overlapping start/finish markers on loop routes.
   Also consider finding the exact time at the goal distance from the stored
   trackpoints, for runs that go past it. That is more accurate than the Riegel
   estimate the goal comparison uses now.
3. Add GPX export and a share/save workflow, mapping `segment` to GPX track segments. This doubles as the backup path that protects against container wipes.
4. Replace the GitHub URL in the share caption with an App Store or TestFlight link once one exists.
5. Prepare TestFlight metadata and distribution after the physical run gate passes.
6. Add independent local analytics such as personal bests, weekly totals, goals, and pace zones without depending on Strava data.

## Implementation notes worth remembering

**Presenting a share sheet.** Use `.sheet(item:)`, not `.sheet(isPresented:)` with a separately-assigned items array. The original implementation seeded `activityItems` as empty and assigned it in the same state update that flipped the presentation flag, so the sheet could be constructed before the items landed — and a `UIActivityViewController` with no items shows no share destinations at all. `.sheet(item:)` makes the data a precondition of presentation. Also avoid `.presentationDetents` on the system share sheet; it interferes with its layout.

**Keep `Models.swift` framework-free.** It is compiled directly by `swiftc` for the pace checks, so importing MapKit or Core Location there would break them. Put coordinate conversion in an extension where MapKit is already imported.

## Product guardrails

- Do not add dependencies for functionality available in Apple frameworks without a strong reason.
- Do not add a backend merely for local analytics or sharing.
- Do not transmit location data by default.
- Do not add Strava credentials or any secret to the repository.
- Do not copy Strava branding, interface, or proprietary formulas.
- Keep social graphics branded as MilePace and based only on first-party run data.
- Avoid inventing "moving time" or auto-pause semantics without making them explicit to the user.
- Preserve existing run history when changing Codable models.
- Never commit `.swiftpm`, DerivedData, Xcode user state, provisioning profiles, or secrets.

## Collaboration convention

Use this repository's GitHub Issues as the durable public backlog and the active coding-agent conversation for rapid implementation. A good issue should contain:

- user-visible outcome;
- acceptance criteria;
- whether it changes stored run data;
- whether it needs physical-device testing;
- screenshots only when a visual state cannot be described clearly.

When handing work back, report:

- files changed;
- build/check results;
- physical-device validation still needed;
- whether changes were committed, pushed, and merged.
