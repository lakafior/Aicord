// swift-tools-version: 6.2

import PackageDescription

/// `aicord-mcp`: an MCP server over stdio that answers from the running
/// Aicord app on this Mac. Read-only; Foundation and Network only.
let package = Package(
  name: "AicordMCP",
  platforms: [.macOS(.v26)],
  products: [
    .executable(name: "aicord-mcp", targets: ["aicord-mcp"])
  ],
  targets: [
    .executableTarget(name: "aicord-mcp")
  ]
)
