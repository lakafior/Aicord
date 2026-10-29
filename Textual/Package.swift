// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "textual",
  platforms: [
    .macOS(.v26),
    .iOS(.v26),
    .tvOS(.v26),
    .watchOS(.v26),
    .visionOS(.v26),
  ],
  products: [
    .library(name: "Textual", targets: ["Textual"])
  ],
  targets: [
    .target(
      name: "Textual",
      resources: [
        .process("Internal/Highlighter/Prism")
      ],
      swiftSettings: [
        .define(
          "TEXTUAL_ENABLE_LINKS",
          .when(platforms: [.macOS, .macCatalyst, .iOS, .watchOS, .visionOS])),
        .define(
          "TEXTUAL_ENABLE_TEXT_SELECTION",
          .when(platforms: [.macOS, .macCatalyst, .iOS, .visionOS])),
      ]
    ),
  ]
)
