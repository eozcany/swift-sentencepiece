import Foundation
import SentencePiece // <- this must match the module name in your XCFramework's module.modulemap

public enum SPError: Error, LocalizedError {
  case createFailed
  case loadFailed(String)
  case encodeFailed(String)
  case decodeFailed(String)

  public var errorDescription: String? {
    switch self {
    case .createFailed:                return "Failed to create SentencePiece processor."
    case .loadFailed(let m):           return "Failed to load SentencePiece model: \(m)"
    case .encodeFailed(let m):         return "Failed to encode: \(m)"
    case .decodeFailed(let m):         return "Failed to decode: \(m)"
    }
  }
}

/// Swift wrapper for the C API declared in `spm_c_api.h`.
/// Exposed by the XCFramework as module `SentencePiece`.
public final class SentencePieceProcessor {

  /// NOTE: In the XCFramework headers, `spm_processor_t` is a typealias of `UnsafeMutableRawPointer`.
  private var handle: spm_processor_t?

  // MARK: - Init / Deinit

  public init(modelData: Data) throws {
    guard let h = spm_processor_new() else { throw SPError.createFailed }
    self.handle = h

    // `spm_processor_load` expects a path. Write data to a temp file.
    let tmpURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("spm-\(UUID().uuidString).model")
    try modelData.write(to: tmpURL, options: .atomic)

    let status: Int32 = tmpURL.path.withCString { cPath in
      spm_processor_load(h, cPath)
    }

    // Best-effort cleanup
    try? FileManager.default.removeItem(at: tmpURL)

    // Convention here: non-zero == success (matches earlier C glue you used)
    guard status != 0 else {
      throw SPError.loadFailed("spm_processor_load returned \(status)")
    }
  }

  public convenience init(modelURL: URL) throws {
    let data = try Data(contentsOf: modelURL)
    try self.init(modelData: data)
  }

  deinit {
    if let h = handle { spm_processor_free(h) }
  }

  // MARK: - IDs / vocab

  public var eosId: Int {
    guard let h = handle else { return -1 }
    return Int(spm_eos_id(h))
  }

  public var bosId: Int {
    guard let h = handle else { return -1 }
    return Int(spm_bos_id(h))
  }

  public var vocabSize: Int {
    guard let h = handle else { return 0 }
    return Int(spm_vocab_size(h))
  }

  // MARK: - Encode / Decode

  public func encode(_ text: String) throws -> [Int] {
    guard let h = handle else { throw SPError.encodeFailed("no handle") }

    // out params: int32_t** ids, size_t* size
    let idsOut = UnsafeMutablePointer<UnsafeMutablePointer<Int32>?>.allocate(capacity: 1)
    idsOut.initialize(to: nil)
    defer { idsOut.deinitialize(count: 1); idsOut.deallocate() }

    var count: Int = 0 // size_t* → Swift Int*

    let status: Int32 = text.withCString { cstr in
      spm_encode(h, cstr, idsOut, &count)
    }

    guard status != 0, let idsPtr = idsOut.pointee else {
      throw SPError.encodeFailed("spm_encode failed, status \(status)")
    }
    defer { spm_ids_free(idsPtr) }

    let buf = UnsafeBufferPointer(start: idsPtr, count: count)
    return buf.map { Int($0) }
  }

  public func decode(ids: [Int]) throws -> String {
    guard let h = handle else { throw SPError.decodeFailed("no handle") }

    let ids32 = ids.map { Int32($0) }

    // out: char** text
    let txtOut = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: 1)
    txtOut.initialize(to: nil)
    defer { txtOut.deinitialize(count: 1); txtOut.deallocate() }

    let status: Int32 = ids32.withUnsafeBufferPointer { buf in
      guard let base = buf.baseAddress else { return Int32(0) }
      return spm_decode(h, base, ids32.count, txtOut)
    }

    guard status != 0, let cptr = txtOut.pointee else {
      throw SPError.decodeFailed("spm_decode failed, status \(status)")
    }
    defer { spm_string_free(cptr) }

    return String(cString: cptr)
  }
}