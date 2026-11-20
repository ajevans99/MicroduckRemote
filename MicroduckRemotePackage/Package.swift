// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MicroduckRemotePackage",
  platforms: [
    .iOS(.v18),
    .macOS(.v15),
  ],
  products: [
    .library(name: "AppFeature", targets: ["AppFeature"]),
    .library(name: "CockpitFeature", targets: ["CockpitFeature"]),
    .library(name: "DuckDependencies", targets: ["DuckDependencies"]),
    .library(name: "DuckProtocol", targets: ["DuckProtocol"]),
    .library(name: "DuckWebRTC", targets: ["DuckWebRTC"]),
    .library(name: "TelemetryFeature", targets: ["TelemetryFeature"]),
    .library(name: "TricksFeature", targets: ["TricksFeature"]),
  ],
  dependencies: [
    .package(url: "https://github.com/stasel/WebRTC", from: "158.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "1.6.0"),
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.3.0"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.8.0"),
    .package(url: "https://github.com/pointfreeco/swift-identified-collections", from: "1.1.0"),
    .package(url: "https://github.com/pointfreeco/swift-navigation", from: "2.2.0"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.4.0"),
  ],
  targets: [
    .target(
      name: "DuckProtocol",
      dependencies: [
        .product(name: "CasePaths", package: "swift-case-paths"),
        .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
      ]
    ),
    .target(
      name: "DuckDependencies",
      dependencies: [
        "DuckProtocol",
        .product(name: "CasePaths", package: "swift-case-paths"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesMacros", package: "swift-dependencies"),
        .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
        .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
      ]
    ),
    .target(
      name: "DuckWebRTC",
      dependencies: [
        "DuckDependencies",
        "DuckProtocol",
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
        .product(name: "WebRTC", package: "WebRTC"),
      ]
    ),
    .target(
      name: "CockpitFeature",
      dependencies: [
        "DuckDependencies",
        "DuckProtocol",
        .product(name: "CasePaths", package: "swift-case-paths"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
        .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
        .product(name: "SwiftUINavigation", package: "swift-navigation"),
      ]
    ),
    .target(
      name: "TricksFeature",
      dependencies: [
        "DuckDependencies",
        "DuckProtocol",
        .product(name: "CasePaths", package: "swift-case-paths"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
        .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
        .product(name: "SwiftUINavigation", package: "swift-navigation"),
      ]
    ),
    .target(
      name: "TelemetryFeature",
      dependencies: [
        "DuckDependencies",
        "DuckProtocol",
        .product(name: "CasePaths", package: "swift-case-paths"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
        .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
        .product(name: "SwiftUINavigation", package: "swift-navigation"),
      ]
    ),
    .target(
      name: "AppFeature",
      dependencies: [
        "CockpitFeature",
        "DuckDependencies",
        "DuckProtocol",
        "TelemetryFeature",
        "TricksFeature",
        .product(name: "CasePaths", package: "swift-case-paths"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
        .product(name: "SwiftUINavigation", package: "swift-navigation"),
      ]
    ),
    .testTarget(
      name: "DuckProtocolTests",
      dependencies: [
        "DuckProtocol",
        .product(name: "CustomDump", package: "swift-custom-dump"),
      ]
    ),
    .testTarget(
      name: "CockpitFeatureTests",
      dependencies: [
        "CockpitFeature",
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ]
    ),
    .testTarget(
      name: "TricksFeatureTests",
      dependencies: [
        "TricksFeature",
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ]
    ),
  ]
)
