import Foundation
import SentencePieceKit

enum TokenizerError: LocalizedError {
    case fileNotFound(String)
    case initFailed(String)
    case encodeFailed(String)
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let f): return "Tokenizer file not found: \(f)"
        case .initFailed(let m):   return "Tokenizer init failed: \(m)"
        case .encodeFailed(let m): return "Encoding failed: \(m)"
        case .decodeFailed(let m): return "Decoding failed: \(m)"
        }
    }
}

final class LLMTokenizer {
    private let sp: SentencePieceProcessor

    // expose IDs for your generation loop
    let eosTokenID: Int
    let bosTokenID: Int
    let vocabSize: Int

    init() throws {
        // Load tokenizer.model from the app bundle
        guard let url = Bundle.main.url(forResource: "tokenizer", withExtension: "model") else {
            throw TokenizerError.fileNotFound("tokenizer.model")
        }

        do {
            // You can also do: try SentencePieceProcessor(modelData: Data(contentsOf: url))
            self.sp = try SentencePieceProcessor(modelURL: url)
        } catch {
            throw TokenizerError.initFailed(error.localizedDescription)
        }

        self.eosTokenID = sp.eosId
        self.bosTokenID = sp.bosId
        self.vocabSize  = sp.vocabSize
    }

    func encode(_ text: String) throws -> [Int] {
        do {
            return try sp.encode(text)
        } catch {
            throw TokenizerError.encodeFailed(error.localizedDescription)
        }
    }

    func decode(tokens: [Int]) throws -> String {
        do {
            return try sp.decode(ids: tokens)
        } catch {
            throw TokenizerError.decodeFailed(error.localizedDescription)
        }
    }

    /// Same template you used before (adjust if your chat formatting differs)
    func applyChatTemplate(_ messages: [[String: String]], addGenerationPrompt: Bool) -> String {
        var formatted = ""
        let B_INST = "[INST]"
        let E_INST = "[/INST]"
        let B_SYS = "<<SYS>>\n"
        let E_SYS = "\n<</SYS>>\n\n"

        if let system = messages.first(where: { $0["role"] == "system" })?["content"] {
            formatted += B_SYS + system + E_SYS
        }

        for m in messages {
            switch m["role"] {
            case "user":
                formatted += B_INST + (m["content"] ?? "") + E_INST
            case "assistant":
                formatted += " " + (m["content"] ?? "")
            default:
                break
            }
        }
        if addGenerationPrompt { formatted += " " }
        return formatted
    }
}