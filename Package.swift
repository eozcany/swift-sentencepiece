// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "swift-sentencepiece",
  platforms: [.iOS(.v15)],
  products: [
    .library(name: "SentencePieceKit", targets: ["SentencePieceKit"]),
  ],
  targets: [
    .binaryTarget(
      name: "SentencePiece",
      path: "XCFrameworks/SentencePiece.xcframework"
    ),
    .target(
      name: "SentencePieceKit",
      dependencies: ["SentencePiece"],
      path: "Sources/SentencePieceKit"
    ),
  ]
)