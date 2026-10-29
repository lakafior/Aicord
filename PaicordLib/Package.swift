// swift-tools-version: 6.2

import CompilerPluginSupport
import PackageDescription

let package = Package(
  name: "PaicordLib",
  platforms: [
    .macOS(.v26),
    .iOS(.v26),
    .tvOS(.v26),
    .watchOS(.v26),
  ],
  products: [
    .library(
      name: "PaicordLib",
      targets: ["PaicordLib"]
    ),
    .library(
      name: "DiscordCore",
      targets: ["DiscordCore"]
    ),
    .library(
      name: "DiscordHTTP",
      targets: ["DiscordHTTP"]
    ),
    .library(
      name: "DiscordGateway",
      targets: ["DiscordGateway"]
    ),
    .library(
      name: "DiscordModels",
      targets: ["DiscordModels"]
    ),
    .library(
      name: "DiscordUtilities",
      targets: ["DiscordUtilities"]
    ),
    .library(
      name: "DiscordAuth",
      targets: ["DiscordAuth"]
    ),
  ],
  traits: [
    "Non64BitSystemsCompatibility"
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-log.git", from: "1.5.2"),
    .package(
      url: "https://github.com/swiftlang/swift-syntax.git",
      "509.0.0"..<"603.0.0"
    ),
    .package(url: "https://github.com/facebook/zstd.git", from: "1.5.7"),
    .package(
      url: "https://github.com/apple/swift-protobuf.git",
      from: "1.27.0"
    ),
  ],
  targets: [
    .target(
      name: "PaicordLib",
      dependencies: [
        .target(name: "DiscordAuth"),
        .target(name: "DiscordHTTP"),
        .target(name: "DiscordCore"),
        .target(name: "DiscordGateway"),
        .target(name: "DiscordModels"),
        .target(name: "DiscordUtilities"),
      ],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "DiscordCore",
      dependencies: [
        .product(name: "Logging", package: "swift-log")
      ],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "DiscordHTTP",
      dependencies: [
        .target(name: "DiscordModels")
      ],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "DiscordGateway",
      dependencies: [
        .product(name: "libzstd", package: "zstd"),
        .target(name: "DiscordHTTP"),
      ],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "DiscordModels",
      dependencies: [
        .target(name: "DiscordCore"),
        .target(name: "UnstableEnumMacro"),
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
      ],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "DiscordUtilities",
      dependencies: [
        .target(name: "DiscordModels")
      ],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "DiscordAuth",
      dependencies: [
        .target(name: "DiscordModels")
      ],
      swiftSettings: swiftSettings
    ),
    .executableTarget(
      name: "TestCode",
      dependencies: [
        .target(name: "PaicordLib")
      ],
      swiftSettings: swiftSettings
    ),
    .macro(
      name: "UnstableEnumMacro",
      dependencies: [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
      ],
      path: "./Macros/UnstableEnumMacro",
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "DiscordBMTests",
      dependencies: [
        .target(name: "PaicordLib")
      ],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "MacroTests",
      dependencies: [
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
        .target(name: "UnstableEnumMacro"),
      ],
      swiftSettings: swiftSettings
    ),
  ]
)

var featureFlags: [SwiftSetting] {
  [
    /// https://github.com/apple/swift-evolution/blob/main/proposals/0335-existential-any.md
    /// Require `any` for existential types.
    .enableUpcomingFeature("ExistentialAny")
    //		.define("DISCORDBM_ENABLE_LOGGING_DURING_DECODE", .when(configuration: .debug)),
  ]
}

var swiftSettings: [SwiftSetting] {
  featureFlags
}
