import Foundation
import SentencePiece // <- the C module from your module.modulemap

public enum SPError: Error, LocalizedError {
    case createFailed
    case loadFailed(String)
    case encodeFailed(String)
    case decodeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .createFailed: return "Failed to create SentencePiece processor."
        case .loadFailed(let m): return "Failed to load SentencePiece model: \(m)"
        case .encodeFailed(let m): return "Failed to encode: \(m)"
        case .decodeFailed(let m): return "Failed to decode: \(m)"
        }
    }
}

/// Thin Swift wrapper over the C API in sentencepiece_c.h.
/// Note: the exact function names come from SentencePiece's `sentencepiece_c.h`.
/// If your local header uses slightly different names, adjust below accordingly.
public final class SentencePieceProcessor {
    private var handle: OpaquePointer?

    public init(modelData: Data) throws {
        // C API typically loads from a file path.
        // Write the model to a cache file and point the C API at it.
        let url = try Self.persistModelToTemp(data: modelData)
        try self.load(path: url.path)
    }

    public init(modelURL: URL) throws {
        try self.load(path: modelURL.path)
    }

    private func load(path: String) throws {
        // 1) Create processor
        guard let h = sentencepiece_processor_new() else {
            throw SPError.createFailed
        }
        self.handle = h

        // 2) Load model
        // int sentencepiece_processor_load(SentencePieceProcessor* p, const char* filename);
        let rc = path.withCString { cPath in
            sentencepiece_processor_load(h, cPath)
        }
        guard rc == 0 else {
            throw SPError.loadFailed("rc=\(rc)")
        }
    }

    deinit {
        if let h = handle {
            sentencepiece_processor_free(h)
        }
    }

    public func encodeIds(_ text: String) throws -> [Int32] {
        guard let h = handle else { throw SPError.encodeFailed("no handle") }

        // Typical API:
        // int sentencepiece_encode(SentencePieceProcessor* p,
        //                          const char* input,
        //                          int **ids, size_t *size);

        var idsPtr: UnsafeMutablePointer<Int32>?
        var sz: Int = 0
        let rc = text.withCString { cText in
            sentencepiece_encode(h, cText, &idsPtr, &sz)
        }
        guard rc == 0, let ptr = idsPtr, sz > 0 else {
            throw SPError.encodeFailed("rc=\(rc)")
        }
        let buffer = UnsafeBufferPointer(start: ptr, count: sz)
        let ids = Array(buffer)
        sentencepiece_ids_free(idsPtr, sz) // free from C API (helper provided by c header)
        return ids
    }

    public func decodeIds(_ ids: [Int32]) throws -> String {
        guard let h = handle else { throw SPError.decodeFailed("no handle") }

        // Typical API:
        // int sentencepiece_decode(SentencePieceProcessor* p,
        //                          const int *ids, size_t size,
        //                          char **output);

        var outPtr: UnsafeMutablePointer<CChar>?
        let rc = ids.withUnsafeBufferPointer { buf in
            sentencepiece_decode(h, buf.baseAddress, buf.count, &outPtr)
        }
        guard rc == 0, let cstr = outPtr else {
            throw SPError.decodeFailed("rc=\(rc)")
        }
        let text = String(cString: cstr)
        sentencepiece_string_free(outPtr) // free from C API
        return text
    }

    public var eosId: Int32 {
        guard let h = handle else { return -1 }
        return sentencepiece_eos_id(h)
    }

    public var bosId: Int32 {
        guard let h = handle else { return -1 }
        return sentencepiece_bos_id(h)
    }

    public var vocabSize: Int32 {
        guard let h = handle else { return 0 }
        return sentencepiece_vocab_size(h)
    }

    private static func persistModelToTemp(data: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("spm-\(UUID().uuidString).model")
        try data.write(to: url, options: .atomic)
        return url
    }
}