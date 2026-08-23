import XCTest
@testable import SwiftTerm

/// A hardware Korean keyboard hands the fork bare compatibility jamo for
/// everything after 초성+중성. Compound vowels (겹모음) arrive that way just
/// like 받침 do, so the same local composition has to close them up.
final class HangulCompoundVowelTests: XCTestCase {

    // MARK: the seven compound vowels

    func testAllSevenCompoundVowelsClose() {
        XCTAssertEqual(HangulPreedit.composeDocument("오ㅏ"), "와")
        XCTAssertEqual(HangulPreedit.composeDocument("오ㅐ"), "왜")
        XCTAssertEqual(HangulPreedit.composeDocument("오ㅣ"), "외")
        XCTAssertEqual(HangulPreedit.composeDocument("우ㅓ"), "워")
        XCTAssertEqual(HangulPreedit.composeDocument("우ㅔ"), "웨")
        XCTAssertEqual(HangulPreedit.composeDocument("우ㅣ"), "위")
        XCTAssertEqual(HangulPreedit.composeDocument("으ㅣ"), "의")
    }

    func testCompoundVowelKeepsTheLeadingConsonant() {
        XCTAssertEqual(HangulPreedit.composeDocument("고ㅏ"), "과")
        XCTAssertEqual(HangulPreedit.composeDocument("두ㅓ"), "둬")
        XCTAssertEqual(HangulPreedit.composeDocument("스ㅣ"), "싀")
    }

    func testCompoundVowelThenFinalConsonant() {
        XCTAssertEqual(HangulPreedit.composeDocument("고ㅏㅇ"), "광")
        XCTAssertEqual(HangulPreedit.composeDocument("무ㅓㄴ"), "뭔")
    }

    // MARK: vowels that must NOT merge

    func testVowelsThatAreNotACompoundStayBare() {
        XCTAssertEqual(HangulPreedit.composeDocument("아ㅏ"), "아ㅏ")
        XCTAssertEqual(HangulPreedit.composeDocument("어ㅓ"), "어ㅓ")
        XCTAssertEqual(HangulPreedit.composeDocument("이ㅣ"), "이ㅣ")
    }

    /// ㅐ and ㅔ have their own keys in the two-set layout. Merging ㅏ+ㅣ here
    /// would turn "아이" into "애".
    func testSimpleVowelPlusIDoesNotBecomeAeOrE() {
        XCTAssertEqual(HangulPreedit.composeDocument("가ㅣ"), "가ㅣ")
        XCTAssertEqual(HangulPreedit.composeDocument("거ㅣ"), "거ㅣ")
    }

    /// A compound vowel is already full; nothing further attaches to it.
    func testCompoundVowelDoesNotTakeAnotherVowel() {
        XCTAssertEqual(HangulPreedit.composeDocument("와ㅏ"), "와ㅏ")
        XCTAssertEqual(HangulPreedit.composeDocument("의ㅣ"), "의ㅣ")
    }

    // MARK: the existing 받침 rules must survive

    func testSyllableWithAFinalStillResyllabifies() {
        XCTAssertEqual(HangulPreedit.composeDocument("온ㅏ"), "오나")
        XCTAssertEqual(HangulPreedit.composeDocument("간ㅏ"), "가나")
        XCTAssertEqual(HangulPreedit.composeDocument("닭ㅏ"), "달가")
    }

    func testBatchimCompositionIsUnchanged() {
        XCTAssertEqual(HangulPreedit.composeDocument("가ㄱ"), "각")
        XCTAssertEqual(HangulPreedit.composeDocument("다ㄹㄱ"), "닭")
        XCTAssertEqual(HangulPreedit.composeDocument("각ㄱ"), "각ㄱ")
    }

    // MARK: split still holds back only the volatile syllable

    func testCompoundVowelSyllableIsTheComposingTail() {
        let result = HangulPreedit.split("오ㅏ")
        XCTAssertEqual(result.commit, "")
        XCTAssertEqual(result.composing, "와")
    }

    func testTextBeforeTheCompoundVowelCommits() {
        let result = HangulPreedit.split("사과 고ㅏ")
        XCTAssertEqual(result.commit, "사과 ")
        XCTAssertEqual(result.composing, "과")
    }

    // MARK: the tables themselves

    func testDoubleMedialTable() {
        XCTAssertEqual(HangulComposition.doubleMedial(first: "ㅗ", second: "ㅏ"), "ㅘ")
        XCTAssertEqual(HangulComposition.doubleMedial(first: "ㅗ", second: "ㅐ"), "ㅙ")
        XCTAssertEqual(HangulComposition.doubleMedial(first: "ㅗ", second: "ㅣ"), "ㅚ")
        XCTAssertEqual(HangulComposition.doubleMedial(first: "ㅜ", second: "ㅓ"), "ㅝ")
        XCTAssertEqual(HangulComposition.doubleMedial(first: "ㅜ", second: "ㅔ"), "ㅞ")
        XCTAssertEqual(HangulComposition.doubleMedial(first: "ㅜ", second: "ㅣ"), "ㅟ")
        XCTAssertEqual(HangulComposition.doubleMedial(first: "ㅡ", second: "ㅣ"), "ㅢ")
        XCTAssertNil(HangulComposition.doubleMedial(first: "ㅏ", second: "ㅣ"))
        XCTAssertNil(HangulComposition.doubleMedial(first: "ㅗ", second: "ㅓ"))
        XCTAssertNil(HangulComposition.doubleMedial(first: "ㄱ", second: "ㅏ"))
    }

    func testSplitMedialIsTheInverseOfDoubleMedial() {
        for (first, second) in [("ㅗ", "ㅏ"), ("ㅗ", "ㅐ"), ("ㅗ", "ㅣ"),
                                ("ㅜ", "ㅓ"), ("ㅜ", "ㅔ"), ("ㅜ", "ㅣ"),
                                ("ㅡ", "ㅣ")] {
            let a = Character(first), b = Character(second)
            guard let compound = HangulComposition.doubleMedial(first: a, second: b) else {
                return XCTFail("no compound for \(first)+\(second)")
            }
            let parts = HangulComposition.splitMedial(compound)
            XCTAssertEqual(parts?.keep, a)
            XCTAssertEqual(parts?.carry, b)
        }
        XCTAssertNil(HangulComposition.splitMedial("ㅏ"))
    }

    // MARK: replacement, the single-step primitive

    func testReplacementClosesACompoundVowel() {
        XCTAssertEqual(HangulComposition.replacement(for: "오", incoming: "ㅏ"), "와")
        XCTAssertEqual(HangulComposition.replacement(for: "구", incoming: "ㅣ"), "귀")
    }

    func testReplacementReturnsNilWhenVowelsCannotMerge() {
        XCTAssertNil(HangulComposition.replacement(for: "아", incoming: "ㅏ"))
        XCTAssertNil(HangulComposition.replacement(for: "와", incoming: "ㅏ"))
    }
}
