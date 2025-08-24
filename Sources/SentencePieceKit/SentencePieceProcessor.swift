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