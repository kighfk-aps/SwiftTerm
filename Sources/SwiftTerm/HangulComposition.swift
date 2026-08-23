//
//  HangulComposition.swift
//  SwiftTerm
//
//  Narrow local Hangul composition for the hardware-keyboard input path.
//

import Foundation

/// Pure Hangul syllable arithmetic.
///
/// Used only to read the IME's document, never to rewrite it: `HangulPreedit`
/// calls these to work out what a syllable looks like once its bare trailing
/// jamo are attached. See `HangulPreedit` for why the document itself stays
/// exactly as the IME left it.
enum HangulComposition {
    static let choseongOrder: [Character] = [
        "ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ",
        "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ",
    ]

    static let jungseongOrder: [Character] = [
        "ㅏ", "ㅐ", "ㅑ", "ㅒ", "ㅓ", "ㅔ", "ㅕ", "ㅖ", "ㅗ", "ㅘ", "ㅙ",
        "ㅚ", "ㅛ", "ㅜ", "ㅝ", "ㅞ", "ㅟ", "ㅠ", "ㅡ", "ㅢ", "ㅣ",
    ]

    /// Index 0 means "no final consonant".
    static let jongseongOrder: [Character?] = [
        nil, "ㄱ", "ㄲ", "ㄳ", "ㄴ", "ㄵ", "ㄶ", "ㄷ", "ㄹ", "ㄺ", "ㄻ",
        "ㄼ", "ㄽ", "ㄾ", "ㄿ", "ㅀ", "ㅁ", "ㅂ", "ㅄ", "ㅅ", "ㅆ", "ㅇ",
        "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ",
    ]

    private static let baseValue = 0xAC00
    private static let medialCount = jungseongOrder.count
    private static let finalCount = jongseongOrder.count

    struct Syllable {
        let initial: Int
        let medial: Int
        let final: Int

        var finalCharacter: Character? { jongseongOrder[final] }
    }

    static func decompose(_ character: Character) -> Syllable? {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1 else { return nil }
        let value = Int(scalar.value) - baseValue
        guard value >= 0, value < choseongOrder.count * medialCount * finalCount else { return nil }
        return Syllable(
            initial: value / (medialCount * finalCount),
            medial: (value % (medialCount * finalCount)) / finalCount,
            final: value % finalCount)
    }

    static func compose(initial: Int, medial: Int, final: Int) -> Character {
        precondition(initial >= 0 && initial < choseongOrder.count,
                     "leading consonant index out of range")
        precondition(medial >= 0 && medial < medialCount,
                     "vowel index out of range")
        precondition(final >= 0 && final < finalCount,
                     "final consonant index out of range")
        let scalarValue = baseValue + initial * medialCount * finalCount + medial * finalCount + final
        guard let scalar = Unicode.Scalar(scalarValue) else {
            preconditionFailure("unreachable: indices validated above")
        }
        return Character(scalar)
    }

    static func isVowelJamo(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1 else { return false }
        return (0x314F...0x3163).contains(scalar.value)
    }

    static func isConsonantJamo(_ character: Character) -> Bool {
        !isVowelJamo(character) && jongseongIndex(of: character) != nil
    }

    /// True for anything the Korean IME can still be composing: a precomposed
    /// syllable, or a bare compatibility jamo.
    static func isHangulInput(_ character: Character) -> Bool {
        decompose(character) != nil || isVowelJamo(character) || isConsonantJamo(character)
    }

    /// Attaches `jamos` onto `base` one at a time (받침, then 겹받침). Returns
    /// the full replacement string for the base+jamos span; jamo that cannot
    /// attach stay verbatim at the end (다+ㄹㅋ → 달ㅋ).
    static func chainReplacement(base: Character, jamos: String) -> String {
        var current = String(base)
        for jamo in jamos {
            guard let merged = replacement(for: current.last ?? base, incoming: jamo),
                  merged.count == 1 else {
                current.append(jamo)
                continue
            }
            current.removeLast()
            current += merged
        }
        return current
    }

    static func jongseongIndex(of character: Character) -> Int? {
        jongseongOrder.firstIndex(where: { $0 == character })
    }

    static func doubleFinal(first: Character, second: Character) -> Character? {
        switch (first, second) {
        case ("ㄱ", "ㅅ"): return "ㄳ"
        case ("ㄴ", "ㅈ"): return "ㄵ"
        case ("ㄴ", "ㅎ"): return "ㄶ"
        case ("ㄹ", "ㄱ"): return "ㄺ"
        case ("ㄹ", "ㅁ"): return "ㄻ"
        case ("ㄹ", "ㅂ"): return "ㄼ"
        case ("ㄹ", "ㅅ"): return "ㄽ"
        case ("ㄹ", "ㅌ"): return "ㄾ"
        case ("ㄹ", "ㅍ"): return "ㄿ"
        case ("ㄹ", "ㅎ"): return "ㅀ"
        case ("ㅂ", "ㅅ"): return "ㅄ"
        default: return nil
        }
    }

    static func splitFinal(_ finalCharacter: Character) -> (keep: Character, carry: Character)? {
        switch finalCharacter {
        case "ㄳ": return ("ㄱ", "ㅅ")
        case "ㄵ": return ("ㄴ", "ㅈ")
        case "ㄶ": return ("ㄴ", "ㅎ")
        case "ㄺ": return ("ㄹ", "ㄱ")
        case "ㄻ": return ("ㄹ", "ㅁ")
        case "ㄼ": return ("ㄹ", "ㅂ")
        case "ㄽ": return ("ㄹ", "ㅅ")
        case "ㄾ": return ("ㄹ", "ㅌ")
        case "ㄿ": return ("ㄹ", "ㅍ")
        case "ㅀ": return ("ㄹ", "ㅎ")
        case "ㅄ": return ("ㅂ", "ㅅ")
        default: return nil
        }
    }

    /// What should replace `base` (the last storage character) when the single
    /// jamo `incoming` arrives right after it. Returns nil when nothing may
    /// merge and the caller must pass the jamo through untouched.
    ///
    /// Rules mirror standard two-set Korean typing:
    /// - Consonant after a syllable without a final attaches as the final
    ///   (가+ㄱ → 각); a compatible consonant extends an existing single final
    ///   into a double final (돌+ㄱ → 돐). Incompatible consonants start a new
    ///   syllable and pass through.
    /// - A vowel after a syllable carrying a final resyllabifies: for a single
    ///   final the whole consonant moves down (간+ㅏ → 가나); for a double
    ///   final only the second component moves, the first stays as the final
    ///   of the first syllable (닭+ㅏ → 달가).
    static func replacement(for base: Character, incoming: Character) -> String? {
        guard let syl = decompose(base) else { return nil }

        if !isVowelJamo(incoming), let incomingFinal = jongseongIndex(of: incoming), incomingFinal != 0 {
            switch syl.finalCharacter {
            case .none:
                return String(compose(initial: syl.initial, medial: syl.medial, final: incomingFinal))
            case .some(let current):
                guard let extended = doubleFinal(first: current, second: incoming),
                      let extendedIndex = jongseongIndex(of: extended), extendedIndex != 0 else { return nil }
                return String(compose(initial: syl.initial, medial: syl.medial, final: extendedIndex))
            }
        }

        if isVowelJamo(incoming), syl.final != 0,
           let carried = syl.finalCharacter,
           let medialIndex = jungseongOrder.firstIndex(of: incoming) {
            let keepIndex: Int
            let carry: Character
            if let split = splitFinal(carried),
               let kept = jongseongIndex(of: split.keep), kept != 0 {
                keepIndex = kept
                carry = split.carry
            } else {
                keepIndex = 0
                carry = carried
            }
            guard let carryInitial = choseongOrder.firstIndex(of: carry) else { return nil }
            let keptSyllable = compose(initial: syl.initial, medial: syl.medial, final: keepIndex)
            let carriedSyllable = compose(initial: carryInitial, medial: medialIndex, final: 0)
            return String(keptSyllable) + String(carriedSyllable)
        }

        return nil
    }
}
