Guide: Building, Tagging, and Shipping your Swift SentencePiece SPM

0) One‑time prerequisites

# Tools
xcodebuild -version        # Xcode installed
cmake --version            # 3.20+ recommended
ninja --version            # optional but faster

# Get sources
git clone https://github.com/google/sentencepiece.git
git clone https://github.com/leetal/ios-cmake.git   # toolchain for iOS cross-compile


1) Build static libs (device + simulator)

These commands produce libsentencepiece.a for iPhone (arm64) and Simulator (arm64 + x86_64).

cd sentencepiece

# Clean old outputs
rm -rf build-ios && mkdir -p build-ios

### A) iPhoneOS (arm64)
mkdir -p build-ios/iphoneos && cd build-ios/iphoneos
cmake ../.. -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE=../../../ios-cmake/ios.toolchain.cmake \
  -DPLATFORM=OS64 \
  -DARCHS=arm64 \
  -DCMAKE_BUILD_TYPE=Release \
  -DSPM_USE_BUILTIN_PROTOBUF=ON \
  -DSPM_ENABLE_SHARED=OFF
ninja
cd ../..

### B) iOS Simulator (arm64)
mkdir -p build-ios/simulator && cd build-ios/simulator
cmake ../.. -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE=../../../ios-cmake/ios.toolchain.cmake \
  -DPLATFORM=SIMULATOR64 \
  -DARCHS=arm64" \
  -DCMAKE_BUILD_TYPE=Release \
  -DSPM_USE_BUILTIN_PROTOBUF=ON \
  -DSPM_ENABLE_SHARED=OFF
ninja
cd ../..


2) Prepare public headers + module map

SentencePiece ships headers under src/. We’ll collect only what we need and expose a small C shim for Swift.

# From sentencepiece/ (repo root)
mkdir -p build-ios/headers/sentencepiece
cp -a src/*.h build-ios/headers/sentencepiece/

# Umbrella header
cat > build-ios/headers/SentencePieceKit.h << 'EOF'
#pragma once
// Minimal umbrella header – include the public C++ headers.
#include "sentencepiece/processor.h"
EOF

# module.modulemap (so Swift can `import SentencePieceKit`)
cat > build-ios/headers/module.modulemap << 'EOF'
framework module SentencePieceKit {
  umbrella header "SentencePieceKit.h"
  export *
  module * { export * }
}
EOF

3) Create the XCFramework
# (Optional) strip symbols
strip -S -x build-ios/iphoneos/src/libsentencepiece.a || true
strip -S -x build-ios/simulator/src/libsentencepiece.a || true

# Create the XCFramework
xcodebuild -create-xcframework \
  -library build-ios/iphoneos/src/libsentencepiece.a -headers build-ios/headers \
  -library build-ios/simulator/src/libsentencepiece.a -headers build-ios/headers \
  -output build-ios/SentencePiece.xcframework

You should now have: sentencepiece/build-ios/SentencePiece.xcframework

4) Create (or update) your Swift Package repo

Repo name: swift-sentencepiece (your choice).
Structure below keeps everything simple and taggable.

swift-sentencepiece/
├─ Package.swift
├─ README.md
└─ Sources/
   └─ SentencePieceKit/
      ├─ SentencePieceProcessor.swift      # Your Swift-friendly wrapper (thin)
      └─ SentencePiece.xcframework/        # The built framework (copied here)


Copy the XCFramework into your package

# from sentencepiece/ root, copy into your SPM repo
cp -R build-ios/SentencePiece.xcframework \
  /path/to/swift-sentencepiece/Sources/SentencePieceKit/


5) Release a new version (tag)
cd /path/to/swift-sentencepiece
git add -A
git commit -m "Release 0.1.0: add SentencePieceKit XCFramework"
git tag v0.1.0
git push origin main --tags


6) Integrate in an iOS app
	1.	Xcode → File → Add Packages…
	2.	Enter your repo URL (e.g., https://github.com/you/swift-sentencepiece)
	3.	Choose Up to Next Major (starting from v0.1.0)
	4.	Add product SentencePieceKit to your app target
	5.	In code: import SentencePieceKit
	6.	Ensure your tokenizer.model is in the app Copy Bundle Resources


7) Update later (new build or features)
When SentencePiece updates or you need a new slice:

# Re-run Sections 1–3 to rebuild the XCFramework
rm -rf Sources/SentencePieceKit/SentencePiece.xcframework
cp -R /path/to/new/SentencePiece.xcframework Sources/SentencePieceKit/

# If you changed the Swift wrapper or added APIs, edit files in Sources/…

# Bump the version
git add -A
git commit -m "Release 0.2.0: update XCFramework / API"
git tag v0.2.0
git push origin main --tags

Consumers then update the package to v0.2.0 in Xcode.

8) Troubleshooting
	•	“invalid headers path” during -create-xcframework
Ensure build-ios/headers contains both SentencePieceKit.h and module.modulemap.
	•	“No such module ‘SentencePieceKit’” in app
Verify the XCFramework is at Sources/SentencePieceKit/SentencePiece.xcframework and the target path in Package.swift matches.
	•	Undefined symbols for libc++
Keep .linkedLibrary("c++") in Package.swift.
	•	Simulator arch mismatch
Build simulator with -DARCHS="arm64;x86_64".
	•	App can’t find tokenizer.model
Check Target Membership and Copy Bundle Resources.



9) Optional: One‑shot release script

Create scripts/release.sh in the SentencePiece repo to automate 1–3:

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
OUT="$ROOT/build-ios"
TOOLCHAIN="$ROOT/../ios-cmake/ios.toolchain.cmake"

rm -rf "$OUT" && mkdir -p "$OUT"

# iPhoneOS
cmake -S . -B "$OUT/iphoneos" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" -DPLATFORM=OS64 -DARCHS=arm64 \
  -DCMAKE_BUILD_TYPE=Release -DSPM_USE_BUILTIN_PROTOBUF=ON -DSPM_ENABLE_SHARED=OFF
cmake --build "$OUT/iphoneos" --config Release

# Simulator
cmake -S . -B "$OUT/simulator" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" -DPLATFORM=SIMULATOR64 -DARCHS="arm64;x86_64" \
  -DCMAKE_BUILD_TYPE=Release -DSPM_USE_BUILTIN_PROTOBUF=ON -DSPM_ENABLE_SHARED=OFF
cmake --build "$OUT/simulator" --config Release

# headers & modulemap
mkdir -p "$OUT/headers/sentencepiece"
cp -a src/*.h "$OUT/headers/sentencepiece/"
cat > "$OUT/headers/SentencePieceKit.h" <<'EOF'
#pragma once
#include "sentencepiece/processor.h"
EOF
cat > "$OUT/headers/module.modulemap" <<'EOF'
framework module SentencePieceKit {
  umbrella header "SentencePieceKit.h"
  export *
  module * { export * }
}
EOF

# XCFramework
xcodebuild -create-xcframework \
  -library "$OUT/iphoneos/src/libsentencepiece.a" -headers "$OUT/headers" \
  -library "$OUT/simulator/src/libsentencepiece.a" -headers "$OUT/headers" \
  -output "$OUT/SentencePiece.xcframework"

echo "✅ XCFramework at: $OUT/SentencePiece.xcframework"

License Notes
	•	SentencePiece is Apache‑2.0. Keep its license text in your repo if you redistribute binaries.
	•	If you add a C shim, license it compatibly and document changes.

    