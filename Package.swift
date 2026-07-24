// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MilePaceCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "MilePaceCore", targets: ["MilePaceCore"])
    ],
    targets: [
        .target(
            name: "MilePaceCore",
            path: "MilePace",
            exclude: [
                "Assets.xcassets",
                "ContentView.swift",
                "RunActivityAttributes.swift",
                "RunActivityController.swift",
                "GoalStore.swift",
                "Info.plist",
                "MilePaceApp.swift",
                "PrivacyInfo.xcprivacy",
                "RunStore.swift",
                "RunTracker.swift"
            ],
            sources: ["Models.swift", "PacePrediction.swift", "RunAccumulator.swift"]
        )
    ]
)
