import Foundation
import SentencePiece // the module exported by your XCFramework

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

/// Thin Swift wrapper for the C API in `spm_c_api.h`.
public final class SentencePieceProcessor {
  private var handle: OpaquePointer?

  // MARK: - Init / Deinit

  public init(modelData: Data) throws {
    // Create processor
    var h: OpaquePointer?
    guard spm_processor_new(&h) else { throw SPError.createFailed }
    self.handle = h

    // Load model from bytes
    let ok: Bool = modelData.withUnsafeBytes { rawBuf in
      guard let base = rawBuf.baseAddress else { return false }
      // Many C APIs take (void*, size_t)
      return spm_processor_load(self.handle, base, modelData.count)
    }
    if !ok { throw SPError.loadFailed("spm_processor_load returned false") }
  }

  public convenience init(modelURL: URL) throws {
    let data = try Data(contentsOf: modelURL)
    try self.init(modelData: data)
  }

  deinit {
    if let h = handle { spm_processor_free(h) }
  }

  // MARK: - IDs / vocab

  public var eosId: Int { Int(spm_eos_id(handle)) }
  public var bosId: Int { Int(spm_bos_id(handle)) }
  public var vocabSize: Int { Int(spm_vocab_size(handle)) }

  // MARK: - Encode / Decode

  public func encode(_ text: String) throws -> [Int] {
    guard let h = handle else { throw SPError.encodeFailed("no handle") }
    // Prepare C string
    let ok: Bool = text.withCString { cstr in
      // Allocate pointer-to-pointer for out param
      let idsOut = UnsafeMutablePointer<UnsafeMutablePointer<Int32>?>.allocate(capacity: 1)
      idsOut.initialize(to: nil)
      defer { idsOut.deinitialize(count: 1); idsOut.deallocate() }

      // size_t* → Swift Int*
      var count: Int = 0

      let success = spm_encode(h, cstr, idsOut, &count)
      guard success else { return false }

      guard let idsPtr = idsOut.pointee else { return false }
      defer { spm_ids_free(idsPtr) }

      // Copy into Swift Array<Int>
      let buf = UnsafeBufferPointer(start: idsPtr, count: count)
      let ints = buf.map { Int($0) }

      // Store into thread-local box for return after leaving withCString
      Thread.current.threadDictionary["__sp_ids__"] = ints
      return true
    }

    guard ok, let ints = Thread.current.threadDictionary["__sp_ids__"] as? [Int] else {
      throw SPError.encodeFailed("spm_encode failed")
    }
    Thread.current.threadDictionary.removeObject(forKey: "__sp_ids__")
    return ints
  }

  public func decode(ids: [Int]) throws -> String {
    guard let h = handle else { throw SPError.decodeFailed("no handle") }
    // Convert to Int32[] for C
    let ids32 = ids.map { Int32($0) }

    // out char** and size_t*
    let txtOut = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: 1)
    txtOut.initialize(to: nil)
    defer { txtOut.deinitialize(count: 1); txtOut.deallocate() }
    var outLen: Int = 0

    let ok = ids32.withUnsafeBufferPointer { buf -> Bool in
      guard let base = buf.baseAddress else { return false }
      return spm_decode(h, base, ids32.count, txtOut, &outLen)
    }
    guard ok, let cstr = txtOut.pointee else {
      throw SPError.decodeFailed("spm_decode failed")
    }
    defer { spm_string_free(cstr) }

    // Construct Swift String from UTF‑8 C buffer
    let text = String(cString: cstr)
    return text
  }
}