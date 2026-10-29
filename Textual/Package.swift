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
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.3.1"),
    .package(url: "https://github.com/gonzalezreal/swiftui-math", from: "0.1.0"),
  ],
  targets: [
    .target(
      name: "Textual",
      dependencies: [
        .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
        .product(name: "SwiftUIMath", package: "swiftui-math"),
      ],
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
