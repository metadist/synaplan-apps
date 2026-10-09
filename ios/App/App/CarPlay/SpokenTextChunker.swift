import Foundation

/// Turns a streamed markdown answer into speakable sentences, so speech can
/// start while the rest of the answer is still arriving.
struct SpokenTextChunker {
    /// Shorter fragments are merged with the next sentence to avoid choppy audio.
    static let minimumSentenceLength = 24

    private var buffer = ""
    private var insideCodeBlock = false

    /// Appends a streamed delta and returns the sentences that are complete.
    mutating func append(_ delta: String) -> [String] {
        buffer += delta
        return drain(final: false)
    }

    /// Returns whatever is left once the stream has completed.
    mutating func finish() -> [String] {
        drain(final: true)
    }

    private mutating func drain(final: Bool) -> [String] {
        var sentences: [String] = []
        while let boundary = nextBoundary(final: final) {
            let raw = String(buffer[..<boundary])
            buffer.removeSubrange(..<boundary)
            let spoken = speakable(raw)
            if !spoken.isEmpty {
                sentences.append(spoken)
            }
        }
        if final {
            let spoken = speakable(buffer)
            buffer = ""
            if !spoken.isEmpty {
                sentences.append(spoken)
            }
        }
        return sentences
    }

    /// End index of the next complete sentence or line, if any.
    private func nextBoundary(final: Bool) -> String.Index? {
        var index = buffer.startIndex
        while index < buffer.endIndex {
            let character = buffer[index]
            let next = buffer.index(after: index)
            if character == "\n" {
                return next
            }
            if ".!?…".contains(character), next < buffer.endIndex, buffer[next].isWhitespace {
                let length = buffer.distance(from: buffer.startIndex, to: next)
                if length >= Self.minimumSentenceLength {
                    return next
                }
            }
            index = next
        }
        return nil
    }

    /// Strips markdown, links, memory badges, and code so only prose is spoken.
    private mutating func speakable(_ raw: String) -> String {
        var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("```") {
            insideCodeBlock.toggle()
            return ""
        }
        if insideCodeBlock || line.isEmpty {
            return ""
        }
        if line.hasPrefix("|") || line.allSatisfy({ "-|: ".contains($0) }) {
            return ""
        }

        let replacements: [(String, String)] = [
            (#"\[Memory:\d+\]"#, ""),
            (#"!\[[^\]]*\]\([^)]*\)"#, ""),
            (#"\[([^\]]+)\]\([^)]*\)"#, "$1"),
            (#"https?://\S+"#, ""),
            (#"`([^`]*)`"#, "$1"),
            (#"^#{1,6}\s*"#, ""),
            (#"^\s*([-*+]|\d+[.)])\s+"#, ""),
            (#"^>\s*"#, ""),
            (#"(\*\*|__|\*|_|~~)"#, ""),
        ]
        for (pattern, template) in replacements {
            line = line.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return line
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
