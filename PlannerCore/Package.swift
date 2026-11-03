// swift-tools-version:5.9
import PackageDescription

// 純規則層：不依賴 SwiftUI / SwiftData，可用 `swift test` 獨立驗證。
let package = Package(
    name: "PlannerCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "PlannerCore", targets: ["PlannerCore"])],
    targets: [
        .target(name: "PlannerCore"),
        .testTarget(name: "PlannerCoreTests", dependencies: ["PlannerCore"]),
    ]
)
