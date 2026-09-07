//
//  HangulPreedit.swift
//  SwiftTerm
//
//  Splits the IME document into what the PTY may safely receive and what is
//  still composed and therefore belongs on screen only.
//
// The rules come from on-device iPadOS traces (2026-08-23). A Korean hardware
// keyboard delivers the leading jamo of a syllable as a bare `insertText`,
// repairs 초성+중성 itself with select/delete/insert spans, and never attaches
// 받침 at all — bare trailing consonants just sit in the document.
//
// Earlier revisions of this fork rewrote the document to attach those 받침.
// That desynced the IME's own model and corrupted the very next span it
// selected. Nothing here mutates the document: these are pure functions over a
// snapshot of it.
enum HangulPreedit {

    /// The document as a reader should see it: bare trailing consonants merged
    /// into the syllable in front of them.
    ///
    ///     "가ㄱ"         -> "각"
    ///     "다ㄹㄱ"       -> "닭"
    ///     "각 ㄲ"        -> "각 ㄲ"   (a jamo after a space starts a syllable)
    ///     "각ㄱ"         -> "각ㄱ"    (ㄱ+ㄱ is not a double final)
    static func composeDocument(_ storage: String) -> String {
        var out = ""
        for character in storage {
            if HangulComposition.isHangulInput(character),
               let base = out.last,
               let merged = HangulComposition.replacement(for: base, incoming: character) {
                out.removeLast()
                out += merged
            } else {
                out.append(character)
            }
        }
        return out
    }

    /// Records, for each storage character, the resulting character count after
    /// composing all characters up to (and including) that one via `composeDocument`.
    /// Useful for mapping between storage indices and composed lengths during
    /// backspace operations.
    /// - Parameter storage: The full IME document string.
    /// - Returns: An array where `lengths[i]` is the composed character count of
    ///   `storage[..<storage.index(after: i)]` after passing through `composeDocument`.
    static func composedLengths(_ storage: String) -> [Int] {
        var lengths: [Int] = []
        var composed = ""
        for character in storage {
            if HangulComposition.isHangulInput(character),
               let base = composed.last,
               let merged = HangulComposition.replacement(for: base, incoming: character) {
                composed.removeLast()
                composed += merged
            } else {
                composed.append(character)
            }
            lengths.append(composed.unicodeScalars.count)
        }
        return lengths
    }

    /// Splits the composed document at the last point that can still change.
    ///
    /// Only the final syllable is volatile: a following consonant turns it into
    /// a 받침 (가 → 각), a following vowel resyllabifies it (닭 → 달가), and the
    /// IME's own repair spans never reach further back. Everything before it is
    /// settled and safe to send.
    ///
    /// When the document does not end in Hangul there is nothing to wait for,
    /// so Latin letters, digits, spaces and punctuation commit immediately and
    /// typing English keeps its usual keystroke-by-keystroke feel.
    static func split(_ storage: String) -> (commit: String, composing: String) {
        let composed = composeDocument(storage)
        guard let lastTyped = storage.last,
              HangulComposition.isHangulInput(lastTyped),
              composed.last != nil else {
            return (composed, "")
        }
        var commit = composed
        let composing = commit.removeLast()
        return (commit, String(composing))
    }

    /// Splits `storage`, but never lets text that already reached the terminal
    /// slide back into composition.
    ///
    /// The plain `split` rule looks only at the document. When the IME deletes
    /// a committed space together with the bare jamo after it — which is how
    /// it starts a syllable following a space — the syllable in front would
    /// briefly become volatile again, costing a DEL and a retype for text the
    /// remote already had correct. Holding the commit point at whatever was
    /// sent, for as long as the document still begins with it, keeps those
    /// bytes where they are.
    static func settle(_ storage: String, alreadySent: String) -> (commit: String, composing: String) {
        let composed = composeDocument(storage)
        let natural = split(storage).commit
        let stillSent = zip(composed, alreadySent).prefix(while: { $0 == $1 }).count
        let commitCount = max(natural.count, stillSent)
        return (String(composed.prefix(commitCount)), String(composed.dropFirst(commitCount)))
    }

    /// Calculates the new storage string after a backspace operation.
    /// - Parameters:
    ///   - storage: The current IME document string.
    ///   - alreadySent: The text that has already been sent to the PTY.
    /// - Returns: The new storage string with the appropriate character(s) removed.
    static func backspace(_ storage: String, alreadySent: String) -> String {
        let (commit, composing) = settle(storage, alreadySent: alreadySent)

        // composing이 비어 있지 않다면: 조합 중 — 자모 단위로 지운다
        if !composing.isEmpty {
            // commit.count에 해당하는 저장소 분할 지점 k를 찾는다
            let lengths = composedLengths(storage)
            var k = storage.count  // 기본값: 전체가 여전히 조합 중
            if !commit.isEmpty {
                for i in 0..<lengths.count {
                    if lengths[i] >= commit.count {
                        k = i + 1
                        break
                    }
                }
            } else {
                k = 0
            }
            let tailStartIndex = storage.index(storage.startIndex, offsetBy: k)
            let tail = String(storage[tailStartIndex...])

            if tail.count >= 2 {
                // tail에서 마지막 문자 하나를 뗀 것
                let prefix = String(storage.prefix(k))
                return prefix + String(tail.dropLast())
            } else if tail.count == 1 {
                // HangulComposition.removeLastJamo(tail의 그 한 글자)가 non-nil 결과 r을 주면
                if let r = HangulComposition.removeLastJamo(tail.first!) {
                    let prefix = String(storage.prefix(k))
                    return prefix + r
                }
                // nil이면 (조합 불가능한 단일 문자, 이론상 발생 안 하지만 방어적으로)
                let prefix = String(storage.prefix(k))
                return prefix
            } else {
                // tail이 비어있으면 commit 그대로
                return String(commit)
            }
        }

        // composing이 비어 있다면: 확정분 — 글자 단위로 지운다
        if commit.isEmpty {
            return ""
        } else {
            // commit에서 마지막 글자를 뗀 길이(commit.count - 1)에 해당하는
            // 저장소 분할 지점을 composedLengths에서 찾아 그 앞까지 자른다
            let targetLength = commit.count - 1
            if targetLength == 0 {
                return ""
            }
            let lengths = composedLengths(storage)
            var splitIndex = storage.count
            for i in 0..<lengths.count {
                if lengths[i] == targetLength {
                    splitIndex = i + 1
                }
            }
            return String(storage.prefix(splitIndex))
        }
    }

    /// What the wire needs so that the text already written to the PTY becomes
    /// `commit`.
    struct WireEdit: Equatable {
        /// Characters to erase, one DEL each. Non-zero only when the user
        /// deletes text that really was written out.
        let deletions: Int
        /// Text to append after those erasures.
        let insertion: String
    }

    /// Diffs what was sent against what should now stand. Because `sent` is a
    /// faithful record of the bytes the terminal received, the deletion count
    /// cannot drift the way a guess about IME intent can.
    static func wireEdit(sent: String, commit: String) -> WireEdit {
        let common = zip(sent, commit).prefix(while: { $0 == $1 }).count
        return WireEdit(deletions: sent.count - common,
                        insertion: String(commit.dropFirst(common)))
    }
}