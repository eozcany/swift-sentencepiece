// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "swift-sentencepiece",
  platforms: [.iOS(.v16)],
  products: [
    // This is the Swift module your app will import:
    .library(name: "SentencePieceKit", targets: ["SentencePieceKit"]),
  ],
  targets: [
    // Binary XCFramework that exports C symbols and a module.modulemap named "SentencePiece"
    .binaryTarget(
      name: "SentencePiece",
      path: "XCFrameworks/SentencePiece.xcframework"
    ),

    // Swift wrapper target that depends on the C binary:
    .target(
      name: "SentencePieceKit",
      dependencies: ["SentencePiece"],
      path: "Sources/SentencePieceKit"
    ),

    // (Optional) simple SwiftPM test target to smoke‑test locally
    .testTarget(
      name: "SentencePieceKitTests",
      dependencies: ["SentencePieceKit"]
    ),
  ]
)