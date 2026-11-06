import Foundation

/// A word in the prompt text, normalized for matching against speech.
public struct ScriptToken: Equatable, Sendable {
    public let word: String
    /// UTF-16 range in the prompt text.
    public let range: NSRange
}

public enum ScriptTokenizer {
    public static func tokens(in text: String) -> [ScriptToken] {
        var tokens: [ScriptToken] = []
        let ns = text as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byWords, .localized]) { word, range, _, _ in
            guard let word else { return }
            let normalized = normalize(word)
            if !normalized.isEmpty { tokens.append(ScriptToken(word: normalized, range: range)) }
        }
        return tokens
    }

    /// Words of a transcript, normalized the same way as script tokens.
    public static func words(in text: String) -> [String] {
        tokens(in: text).map(\.word)
    }

    static func normalize(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }
}

/// Follows a reader through the script by aligning the tail of the live
/// transcript with script words. Robust to misheard, skipped, and extra words.
public struct ScriptFollower: Sendable {
    public let tokens: [ScriptToken]
    /// Index of the last script word the reader has said, or -1 before the first.
    public private(set) var lastMatchedIndex: Int = -1

    /// How many trailing transcript words to align.
    public var tailLength = 6
    /// How far ahead of the last match to look during normal reading.
    public var lookAhead = 40

    public init(text: String) {
        self.tokens = ScriptTokenizer.tokens(in: text)
    }

    /// Re-anchors after manual scrolls or cue jumps.
    public mutating func reset(toUTF16Offset offset: Int) {
        lastMatchedIndex = (tokens.lastIndex { $0.range.location < offset }) ?? -1
    }

    /// Feeds the latest transcript words. Returns the matched script token when
    /// the position moved.
    @discardableResult
    public mutating func update(transcriptWords: [String]) -> ScriptToken? {
        let tail = Array(transcriptWords.suffix(tailLength))
        guard !tail.isEmpty, !tokens.isEmpty else { return nil }

        let localStart = max(0, lastMatchedIndex - 3)
        let localEnd = min(tokens.count - 1, lastMatchedIndex + lookAhead)
        let required = min(2, tail.count)

        var best = bestEnd(for: tail, in: localStart...max(localStart, localEnd), minimumScore: required)
        if best == nil {
            // The reader may have skipped ahead or jumped back: search the whole
            // script, but demand a much stronger match.
            best = bestEnd(for: tail, in: 0...(tokens.count - 1), minimumScore: max(required, min(4, tail.count)))
        }
        guard let end = best, end != lastMatchedIndex else { return nil }
        // Small backward wobble from re-recognition is ignored.
        if end < lastMatchedIndex, lastMatchedIndex - end <= 3 { return nil }
        lastMatchedIndex = end
        return tokens[end]
    }

    /// Script index where `tail` best ends, preferring positions nearest the
    /// current place when scores tie.
    private func bestEnd(for tail: [String], in candidates: ClosedRange<Int>, minimumScore: Int) -> Int? {
        var bestIndex: Int?
        var bestScore = 0
        var bestDistance = Int.max
        for end in candidates {
            // The newest spoken word must match the candidate end word.
            guard ScriptFollower.similar(tail.last!, tokens[end].word) else { continue }
            let score = alignmentScore(tail: tail, endingAt: end)
            guard score >= minimumScore else { continue }
            let distance = abs(end - (lastMatchedIndex + 1))
            if score > bestScore || (score == bestScore && distance < bestDistance) {
                bestIndex = end
                bestScore = score
                bestDistance = distance
            }
        }
        return bestIndex
    }

    /// Longest common subsequence between the transcript tail and the script
    /// window ending at `end`, with fuzzy word equality.
    private func alignmentScore(tail: [String], endingAt end: Int) -> Int {
        let windowStart = max(0, end - tail.count - 2)
        let window = tokens[windowStart...end].map(\.word)
        var previous = [Int](repeating: 0, count: window.count + 1)
        for spoken in tail {
            var current = [Int](repeating: 0, count: window.count + 1)
            for (j, word) in window.enumerated() {
                current[j + 1] = ScriptFollower.similar(spoken, word)
                    ? previous[j] + 1
                    : max(previous[j + 1], current[j])
            }
            previous = current
        }
        return previous[window.count]
    }

    static func similar(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let shorter = min(a.count, b.count)
        guard shorter >= 4 else { return false }
        if a.hasPrefix(b) || b.hasPrefix(a) { return true }
        // Shared stem with different endings: "technologies" / "technology".
        let stem = zip(a, b).prefix { $0 == $1 }.count
        if stem >= max(4, shorter - 2) { return true }
        let allowed = shorter >= 7 ? 2 : 1
        return editDistance(a, b, limit: allowed) <= allowed
    }

    static func editDistance(_ a: String, _ b: String, limit: Int) -> Int {
        let a = Array(a), b = Array(b)
        if abs(a.count - b.count) > limit { return limit + 1 }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var previousDiagonal = row[0]
            row[0] = i
            var rowMin = row[0]
            for j in 1...b.count {
                let saved = row[j]
                row[j] = a[i - 1] == b[j - 1] ? previousDiagonal : 1 + min(previousDiagonal, row[j], row[j - 1])
                previousDiagonal = saved
                rowMin = min(rowMin, row[j])
            }
            if rowMin > limit { return limit + 1 }
        }
        return row[b.count]
    }
}

/// Accumulates streaming transcription results: finalized text plus the
/// current volatile guess, which later results replace.
public struct TranscriptBuffer: Sendable {
    public private(set) var finalized: [String] = []
    public private(set) var volatile: [String] = []

    public init() {}

    public mutating func apply(text: String, isFinal: Bool) {
        let words = ScriptTokenizer.words(in: text)
        if isFinal {
            finalized.append(contentsOf: words)
            volatile = []
            // Only the tail matters for alignment.
            if finalized.count > 200 { finalized.removeFirst(finalized.count - 200) }
        } else {
            volatile = words
        }
    }

    public var words: [String] { finalized + volatile }

    public mutating func clear() {
        finalized = []
        volatile = []
    }
}
