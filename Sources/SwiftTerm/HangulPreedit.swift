//
//  HangulPreedit.swift
//  SwiftTerm
//
//  Splits the IME document into what the PTY may safely receive and what is
//  still being composed.
//

import Foundation

/// Turns the IME's document into the two things a terminal needs: the text that
/// is final enough to write to the PTY, and the tail that is still being
/// composed and therefore belongs on screen only.
///
/// The rules come from on-device iPadOS traces (2026-08-23). A Korean hardware
/// keyboard delivers the leading jamo of a syllable as a bare `insertText`,
/// repairs 초성+중성 itself with select/delete/insert spans, and never attaches
/// 받침 at all — bare trailing consonants just sit in the document.
///
/// Earlier revisions of this fork rewrote the document to attach those 받침.
/// That desynced the IME's own model and corrupted the very next span it
/// selected. Nothing here mutates the document: these are pure functions over a
/// snapshot of it.
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
            if HangulComposition.isConsonantJamo(character),
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
