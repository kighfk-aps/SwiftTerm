import XCTest
@testable import SwiftTerm

/// `removeLastJamo` is the piece `deleteBackward` needs to shrink one composing
/// syllable by exactly one jamo, mirroring how a syllable was built up in the
/// first place (see `HangulComposition.replacement(for:incoming:)`).
final class HangulRemoveLastJamoTests: XCTestCase {

    func testDoubleFinalDropsToItsFirstComponent() {
        XCTAssertEqual(HangulComposition.removeLastJamo("닭"), "달")
    }

    func testSingleFinalIsRemoved() {
        XCTAssertEqual(HangulComposition.removeLastJamo("각"), "가")
    }

    func testCompoundVowelDropsToItsFirstComponent() {
        XCTAssertEqual(HangulComposition.removeLastJamo("와"), "오")
    }

    func testSingleVowelSyllableBecomesItsLeadingConsonant() {
        XCTAssertEqual(HangulComposition.removeLastJamo("가"), "ㄱ")
    }

    func testBareConsonantJamoIsRemoved() {
        XCTAssertEqual(HangulComposition.removeLastJamo("ㄱ"), "")
    }

    func testBareVowelJamoIsRemoved() {
        XCTAssertEqual(HangulComposition.removeLastJamo("ㅏ"), "")
    }

    func testNonHangulReturnsNil() {
        XCTAssertNil(HangulComposition.removeLastJamo("a"))
    }
}
