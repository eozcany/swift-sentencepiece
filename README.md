Guide: Building, Tagging, and Shipping your Swift SentencePiece SPM

0) One‑time prerequisites

# Tools
xcodebuild -version        # Xcode installed
cmake --version            # 3.20+ recommended
ninja --version            # optional but faster

# Get sources
git clone https://github.com/google/sentencepiece.git
git clone https://github.com/leetal/ios-cmake.git   # toolchain for iOS cross-compile

 Add a minimal C API (wrapper)

Create two files in the repo root (same level as CMakeLists.txt):

spm_c_api.h

```
#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void* spm_processor_t;

spm_processor_t spm_processor_new(void);
void spm_processor_free(spm_processor_t p);

int spm_processor_load(spm_processor_t p, const char* model_path);

/* Encode UTF-8 text -> ids. Allocates ids; caller frees with spm_ids_free. */
int spm_encode(spm_processor_t p, const char* text, int32_t** ids, size_t* size);
void spm_ids_free(int32_t* ids);

/* Decode ids -> UTF-8 string. Allocates string; caller frees with spm_string_free. */
int spm_decode(spm_processor_t p, const int32_t* ids, size_t size, char** out);
void spm_string_free(char* s);

/* Metadata */
int spm_eos_id(spm_processor_t p);
int spm_bos_id(spm_processor_t p);
int spm_vocab_size(spm_processor_t p);

#ifdef __cplusplus
}
#endif
```

spm_c_api.cc

```
#include "spm_c_api.h"
#include "src/sentencepiece_processor.h"
#include <string>
#include <vector>
#include <cstring>
#include <new>

using sentencepiece::SentencePieceProcessor;

extern "C" {

spm_processor_t spm_processor_new(void) {
  try { return reinterpret_cast<spm_processor_t>(new SentencePieceProcessor()); }
  catch (...) { return nullptr; }
}

void spm_processor_free(spm_processor_t p) {
  delete reinterpret_cast<SentencePieceProcessor*>(p);
}

int spm_processor_load(spm_processor_t p, const char* model_path) {
  if (!p || !model_path) return -1;
  auto* spp = reinterpret_cast<SentencePieceProcessor*>(p);
  auto status = spp->Load(model_path);
  return status.ok() ? 0 : -2;
}

int spm_encode(spm_processor_t p, const char* text, int32_t** ids, size_t* size) {
  if (!p || !text || !ids || !size) return -1;
  auto* spp = reinterpret_cast<SentencePieceProcessor*>(p);
  std::vector<int> vec;
  auto status = spp->Encode(std::string(text), &vec);
  if (!status.ok()) return -2;
  *size = vec.size();
  *ids = (int32_t*)malloc(sizeof(int32_t) * (*size));
  if (!*ids) return -3;
  for (size_t i = 0; i < *size; ++i) (*ids)[i] = static_cast<int32_t>(vec[i]);
  return 0;
}

void spm_ids_free(int32_t* ids) { free(ids); }

int spm_decode(spm_processor_t p, const int32_t* ids, size_t size, char** out) {
  if (!p || !ids || !out) return -1;
  auto* spp = reinterpret_cast<SentencePieceProcessor*>(p);
  std::vector<int> vec(ids, ids + size);
  std::string s;
  auto status = spp->Decode(vec, &s);
  if (!status.ok()) return -2;
  *out = (char*)malloc(s.size() + 1);
  if (!*out) return -3;
  std::memcpy(*out, s.data(), s.size());
  (*out)[s.size()] = '\0';
  return 0;
}

int spm_eos_id(spm_processor_t p)       { return p ? reinterpret_cast<SentencePieceProcessor*>(p)->eos_id()   : -1; }
int spm_bos_id(spm_processor_t p)       { return p ? reinterpret_cast<SentencePieceProcessor*>(p)->bos_id()   : -1; }
int spm_vocab_size(spm_processor_t p)   { return p ? reinterpret_cast<SentencePieceProcessor*>(p)->GetPieceSize() : -1; }

} // extern "C"
```

Teach CMake to build the wrapper (static lib)

Append to the bottom of CMakeLists.txt:

```
# C API mini wrapper
add_library(spm_c_api STATIC spm_c_api.cc)
target_include_directories(spm_c_api PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(spm_c_api PRIVATE sentencepiece-static)
set_target_properties(spm_c_api PROPERTIES OUTPUT_NAME "spm_c_api")
```

Build arm64 slices (device + simulator)
```
# DEVICE (arm64)
rm -rf build-ios && mkdir -p build-ios/iphoneos && cd build-ios/iphoneos
cmake ../.. -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE=../../ios-cmake/ios.toolchain.cmake \
  -DPLATFORM=OS64 \
  -DCMAKE_BUILD_TYPE=Release \
  -DSPM_USE_BUILTIN_PROTOBUF=ON \
  -DSPM_ENABLE_SHARED=OFF
cmake --build . --config Release
cd ../..

# SIMULATOR (arm64 only)
mkdir -p build-ios/sim-arm64 && cd build-ios/sim-arm64
cmake ../.. -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE=../../ios-cmake/ios.toolchain.cmake \
  -DPLATFORM=SIMULATORARM64 \
  -DCMAKE_BUILD_TYPE=Release \
  -DSPM_USE_BUILTIN_PROTOBUF=ON \
  -DSPM_ENABLE_SHARED=OFF
cmake --build . --config Release
cd ../..
```
Artifacts:
	•	build-ios/iphoneos/src/libsentencepiece.a
	•	build-ios/iphoneos/libspm_c_api.a
	•	build-ios/sim-arm64/src/libsentencepiece.a
	•	build-ios/sim-arm64/libspm_c_api.a


 Merge the two static libraries per slice

We’ll create one archive per slice that contains both the upstream lib and our wrapper.

```
# Device merged
libtool -static \
  -o build-ios/iphoneos/libsentencepiece_all.a \
  build-ios/iphoneos/src/libsentencepiece.a \
  build-ios/iphoneos/libspm_c_api.a

# Simulator merged
libtool -static \
  -o build-ios/sim-arm64/libsentencepiece_all.a \
  build-ios/sim-arm64/src/libsentencepiece.a \
  build-ios/sim-arm64/libspm_c_api.a
```

Headers + module map for Swift

```
mkdir -p build-ios/headers

# Umbrella header that includes our C API
cat > build-ios/headers/SentencePiece.h <<'EOF'
#pragma once
#include "spm_c_api.h"
EOF

# Copy our C API header into the headers folder
cp spm_c_api.h build-ios/headers/

# Module map so Swift can: import SentencePiece
cat > build-ios/headers/module.modulemap <<'EOF'
module SentencePiece {
  umbrella header "SentencePiece.h"
  export *
}
EOF
```


Create the XCFramework

```
rm -rf build-ios/SentencePiece.xcframework
xcodebuild -create-xcframework \
  -library build-ios/iphoneos/libsentencepiece_all.a -headers build-ios/headers \
  -library build-ios/sim-arm64/libsentencepiece_all.a -headers build-ios/headers \
  -output build-ios/SentencePiece.xcframework
```

You should now see SentencePiece.xcframework with:
	•	ios-arm64
	•	ios-arm64_i386_x86_64-simulator (Apple sometimes labels the folder like this even when only arm64 symbols exist—OK).


Use from your Swift Package / App
	•	Put the XCFramework under your SPM wrapper repo, e.g. Binary/SentencePiece.xcframework.
	•	Package.swift:

 ```
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "swift-sentencepiece",
  platforms: [.iOS(.v15)],
  products: [
    .library(name: "SentencePieceKit", targets: ["SentencePieceKit"])
  ],
  targets: [
    .binaryTarget(
      name: "SentencePiece",
      path: "Binary/SentencePiece.xcframework"
    ),
    .target(
      name: "SentencePieceKit",
      dependencies: ["SentencePiece"],
      path: "Sources/SentencePieceKit"
    )
  ]
)
```

Your Sources/SentencePieceKit/SentencePieceProcessor.swift should import the module and call the C API names we defined:

```
import Foundation
import SentencePiece

public final class SentencePieceProcessor {
  private var h: OpaquePointer?

  public init() {
    self.h = OpaquePointer(spm_processor_new())
  }
  deinit { spm_processor_free(h) }

  public func load(path: URL) throws {
    guard spm_processor_load(h, path.path) == 0 else { throw SPError.loadFailed(path.path) }
  }

  public func encode(_ text: String) throws -> [Int] {
    var idsPtr: UnsafeMutablePointer<Int32>?
    var count: Int = 0
    guard spm_encode(h, text, &idsPtr, &count) == 0, let p = idsPtr else {
      throw SPError.encodeFailed(text)
    }
    defer { spm_ids_free(p) }
    return (0..<count).map { Int(p[$0]) }
  }

  public func decode(_ ids: [Int]) throws -> String {
    var outPtr: UnsafeMutablePointer<CChar>?
    let rc = ids.withUnsafeBufferPointer { buf in
      spm_decode(h, buf.baseAddress, buf.count, &outPtr)
    }
    guard rc == 0, let c = outPtr else { throw SPError.decodeFailed("") }
    defer { spm_string_free(c) }
    return String(cString: c)
  }

  public var eosId: Int { Int(spm_eos_id(h)) }
  public var bosId: Int { Int(spm_bos_id(h)) }
  public var vocabSize: Int { Int(spm_vocab_size(h)) }
}

public enum SPError: Error {
  case loadFailed(String), encodeFailed(String), decodeFailed(String)
}
```
8) Commit, tag, and consume
	•	Commit the XCFramework and sources to your private or public SPM repo.
	•	Tag a release (e.g., v0.1.0) and point Xcode’s “Add Packages…” to that repo/tag.
	•	Select the library product (your SentencePieceKit) for the app target.
