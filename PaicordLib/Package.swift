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
      name: "DiscordVoice",
      targets: ["DiscordVoice"]
    ),
    .library(
      name: "DiscordModels",
      targets: ["DiscordModels"]
    ),
    .library(
      name: "DiscordUtilities",
      targets: ["DiscordUtilities"]
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
    /// DAVE (E2EE) through the official libdave. Pinned to a commit because
    /// the repository has no tags and `main` moves.
    .package(
      url: "https://github.com/llsc12/DaveKit.git",
      revision: "a4c4e182400f4661259064940b534ea53d8c3e1b"
    ),
    /// libopus built from source. Only the C target (`Copus`) is used.
    .package(
      url: "https://github.com/alta/swift-opus.git",
      revision: "6f3cb6bd3ffed1fe5f06d00a962d5c191a50daf8"
    ),
  ],
  targets: [
    .target(
      name: "PaicordLib",
      dependencies: [
        .target(name: "DiscordHTTP"),
        .target(name: "DiscordCore"),
        .target(name: "DiscordGateway"),
        .target(name: "DiscordModels"),
        .target(name: "DiscordUtilities"),
        .target(name: "DiscordVoice"),
      ],
      swiftSettings: swiftSettings + importsDiscordVoice
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
      name: "DiscordVoice",
      dependencies: [
        .target(name: "DiscordModels"),
        .product(name: "DaveKit", package: "DaveKit"),
        .target(name: "COpusShim"),
      ],
      /// DaveKit is a Swift wrapper built with C++ interop, so importing it
      /// requires the same mode. It stays confined to this target.
      swiftSettings: swiftSettings + [
        .interoperabilityMode(.Cxx),
        .enableExperimentalFeature("CheckImplementationOnly"),
      ]
    ),
    .target(
      name: "COpusShim",
      dependencies: [
        .product(name: "Copus", package: "swift-opus")
      ]
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
    .executableTarget(
      name: "TestCode",
      dependencies: [
        .target(name: "PaicordLib")
      ],
      swiftSettings: swiftSettings + importsDiscordVoice
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
      swiftSettings: swiftSettings + importsDiscordVoice
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

/// `DiscordVoice` is built with C++ interop (for DaveKit) but exposes no C++
/// in its interface; DaveKit is imported `@_implementationOnly`. Modules that
/// import it would otherwise have to enable C++ interop too.
/// The app target passes the same flag in OTHER_SWIFT_FLAGS.
var importsDiscordVoice: [SwiftSetting] {
  [.unsafeFlags(["-Xfrontend", "-disable-cxx-interop-requirement-at-import"])]
}
