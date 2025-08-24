//
//  SentencePieceProcessor.swift
//  SentencePieceKit
//
//  Swift wrapper over the C SentencePiece API exposed by the
//  SentencePiece.xcframework (module name: `SentencePiece`).
//

import Foundation
import SentencePiece   // <-- the binary target/module from your XCFramework

// MARK: - Errors

public enum SPError: Error, LocalizedError {
    case createFailed
    case loadFailed(code: Int32)
    case encodeFailed(code: Int32)
    case decodeFailed(code: Int32)
    case modelFileMissing(String)

    public var errorDescription: String? {
        switch self {
        case .createFailed:
            return "Failed to create SentencePiece processor."
        case .loadFailed(let code):
            return "Failed to load SentencePiece model (status=\(code))."
        case .encodeFailed(let code):
            return "Failed to encode text (status=\(code))."
        case .decodeFailed(let code):
            return "Failed to decode ids (status=\(code))."
        case .modelFileMissing(let name):
            return "Tokenizer model not found in bundle: \(name)."
        }
    }
}

// MARK: - Wrapper

/// Thin Swift wrapper over the C API.
///
/// Required C symbols (provided by your XCFramework):
/// ```c
/// spm_processor_t *spm_processor_new(void);
/// void spm_processor_free(spm_processor_t *);
/// int spm_processor_load(spm_processor_t *, const char *path);
/// int spm_encode(spm_processor_t *, const char *text,
///                          int32_t **out_ids, int32_t *out_size);
/// void spm_ids_free(int32_t *ids);
/// int spm_decode(spm_processor_t *, const int32_t *ids, int32_t size,
///                          char **out_text, int32_t *out_len);
/// void spm_string_free(char *ptr);
/// int32_t spm_eos_id(spm_processor_t *);
/// int32_t spm_bos_id(spm_processor_t *);
/// int32_t spm_vocab_size(spm_processor_t *);
/// ```
public final class SentencePieceProcessor {
    /// Use the exact imported C handle type (seen by Swift as Optional<UnsafeMutableRawPointer>)
    private var handle: spm_processor_t?

    // Optionally guard all calls (C API is not guaranteed thread‑safe).
    private let queue = DispatchQueue(label: "SentencePieceProcessor.serial")

    // MARK: - Lifecycle

    public init() throws {
        guard let p = spm_processor_new() else {
            throw SPError.createFailed
        }
        self.handle = p
    }

    deinit {
        if let p = handle {
            spm_processor_free(p)
        }
    }

    // MARK: - Loading

    /// Load a `.model` file from disk.
    public func load(modelURL: URL) throws {
        let rc: Int32 = modelURL.path.withCString { cstr in
            spm_processor_load(handle, cstr)
        }
        guard rc == 0 else { throw SPError.loadFailed(code: rc) }
    }

    /// Convenience: write model data to a temp file and load it.
    public func load(modelData: Data) throws {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("model")
        try modelData.write(to: tmpURL, options: .atomic)
        do {
            try load(modelURL: tmpURL)
        } catch {
            // best effort cleanup before surfacing error
            try? FileManager.default.removeItem(at: tmpURL)
            throw error
        }
        try? FileManager.default.removeItem(at: tmpURL)
    }

    /// Convenience: load `tokenizer.model` from a bundle.
    public func load(modelNamed name: String = "tokenizer",
                     withExtension ext: String = "model",
                     in bundle: Bundle = .main) throws
    {
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            throw SPError.modelFileMissing("\(name).\(ext)")
        }
        try load(modelURL: url)
    }

    // MARK: - Encode / Decode

    /// Encode UTF‑8 text to token ids (Int32).
    public func encode(text: String) throws -> [Int32] {
        try queue.sync {
            var idsPtr: UnsafeMutablePointer<Int32>?
            var count: Int32 = 0

            let rc = text.withCString { cstr in
                spm_encode(handle, cstr, &idsPtr, &count)
            }
            guard rc == 0, let base = idsPtr, count >= 0 else {
                if let base = idsPtr { spm_ids_free(base) }
                throw SPError.encodeFailed(code: rc)
            }

            let buf = UnsafeBufferPointer(start: base, count: Int(count))
            let out = Array(buf)
            spm_ids_free(base)
            return out
        }
    }

    /// Decode token ids (Int32) back to text.
    public func decode(ids: [Int32]) throws -> String {
        try queue.sync {
            var textPtr: UnsafeMutablePointer<CChar>?
            var len: Int32 = 0

            let rc = ids.withUnsafeBufferPointer { buf in
                spm_decode(handle, buf.baseAddress, Int32(buf.count), &textPtr, &len)
            }
            guard rc == 0, let p = textPtr else {
                if let p = textPtr { spm_string_free(p) }
                throw SPError.decodeFailed(code: rc)
            }

            let s = String(cString: p)   // API returns NUL‑terminated UTF‑8
            spm_string_free(p)
            return s
        }
    }

    // MARK: - Introspection

    public var eosId: Int32 { queue.sync { spm_eos_id(handle) } }
    public var bosId: Int32 { queue.sync { spm_bos_id(handle) } }
    public var vocabSize: Int32 { queue.sync { spm_vocab_size(handle) } }
}

// MARK: - Tiny helpers (optional)

extension SentencePieceProcessor {
    /// Encode to Swift `Int` if that’s easier for callers.
    public func encodeToInt(_ text: String) throws -> [Int] {
        try encode(text: text).map(Int.init)
    }

    /// Decode from Swift `Int` ids.
    public func decodeFromInt(_ ids: [Int]) throws -> String {
        try decode(ids: ids.map(Int32.init))
    }
}