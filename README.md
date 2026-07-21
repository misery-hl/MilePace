# MilePace

MilePace is a deliberately small, local-only iPhone running app. It uses the iPhone's GPS to show:

- distance in miles
- active running time
- current-mile projected pace
- rolling 30-second pace
- automatic mile splits and local run history
- branded post-run image sharing through the native iOS share sheet

There is no account, subscription, analytics SDK, ad SDK, or backend. Run history is stored only in the app's local Application Support directory.

## Run it on an iPhone

1. Open `MilePace.xcodeproj` in Xcode.
2. Select the **MilePace** target, then **Signing & Capabilities**.
3. Choose your Apple Developer team and replace `com.example.MilePace` with a bundle identifier you control.
4. Connect your iPhone, select it as the run destination, and press Run.
5. Accept **While Using the App** and leave **Precise Location** enabled.

Xcode can install the app directly with a normal Apple ID for personal testing. TestFlight distribution requires Apple Developer Program membership and an App Store Connect app record. Install the full Xcode app; the standalone Command Line Tools are not enough for iOS builds.

## TestFlight

1. In Xcode, set a unique bundle identifier and your signing team.
2. Create the matching app in App Store Connect.
3. Select **Any iOS Device (arm64)**, then use **Product > Archive**.
4. In Organizer, choose **Distribute App > App Store Connect > Upload**. Apple documents the current upload requirements in [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).
5. After processing, add yourself as an internal tester. To share with friends who are not App Store Connect users, create an external testing group and submit the build for TestFlight beta review.

Apple's current walkthrough for email invites and public links is [Invite external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/).

Before a broader release, add a support URL and privacy-policy URL in App Store Connect. The privacy policy can accurately state that MilePace sends no run or location data off the device.

## Accuracy and battery behavior

- GPS is filtered to reject stale, highly inaccurate, and implausibly fast samples.
- The prominent mile pace is calculated from the current mile so it is steadier than raw GPS speed.
- “Live pace” uses a rolling window and needs a few seconds of movement before it settles.
- Tracking continues while the screen is locked after a run has started. iOS shows its location indicator, and extended GPS use will consume battery.
- Paused time is excluded from pace and split calculations.

## Development

Check the platform-independent pace engine with the command-line Swift toolchain:

```sh
swift build
swiftc MilePace/Models.swift MilePace/RunAccumulator.swift Tools/VerifyPaceEngine.swift \
  -o /private/tmp/milepace-engine-check
/private/tmp/milepace-engine-check
```

After full Xcode and an iOS simulator runtime are installed, build and run the XCTest suite from Terminal:

```sh
xcodebuild -project MilePace.xcodeproj \
  -scheme MilePace \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  test
```

The pace math lives in `MilePace/RunAccumulator.swift` and is covered by unit tests, including exact interpolation when a GPS segment crosses a mile boundary.

## License

MilePace is open source under the [MIT License](LICENSE).
