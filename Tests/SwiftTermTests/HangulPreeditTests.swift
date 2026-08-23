import XCTest
@testable import SwiftTerm

/// The IME document is never rewritten; these are the pure functions that turn
/// it into what the user should see and what the PTY should receive.
final class HangulPreeditTests: XCTestCase {

    // MARK: composeDocument

    func testBareFinalConsonantAttachesToPrecedingSyllable() {
        XCTAssertEqual(HangulPreedit.composeDocument("가ㄱ"), "각")
    }

    func testTwoBareConsonantsFormADoubleFinal() {
        XCTAssertEqual(HangulPreedit.composeDocument("다ㄹㄱ"), "닭")
        XCTAssertEqual(HangulPreedit.composeDocument("가ㅂㅅ"), "값")
        XCTAssertEqual(HangulPreedit.composeDocument("도ㄹㅅ"), "돐")
    }

    func testConsonantAfterANonSyllableStaysBare() {
        // A jamo following a space is the leading consonant of a new syllable,
        // exactly what iOS shows.
        XCTAssertEqual(HangulPreedit.composeDocument("각 ㄲ"), "각 ㄲ")
        XCTAssertEqual(HangulPreedit.composeDocument("ㄱ"), "ㄱ")
    }

    func testConsonantThatCannotStackStaysBare() {
        XCTAssertEqual(HangulPreedit.composeDocument("각ㄱ"), "각ㄱ")
    }

    func testFullSyllablesPassThroughUnchanged() {
        XCTAssertEqual(HangulPreedit.composeDocument("각 깎 닭 값 "), "각 깎 닭 값 ")
        XCTAssertEqual(HangulPreedit.composeDocument("ls -al"), "ls -al")
        XCTAssertEqual(HangulPreedit.composeDocument(""), "")
    }

    func testComposesOnlyTheTrailingRun() {
        XCTAssertEqual(HangulPreedit.composeDocument("각 깎 다ㄹㄱ"), "각 깎 닭")
    }

    // MARK: split

    func testTrailingHangulIsHeldBackAsComposing() {
        let s = HangulPreedit.split("가ㄱ")
        XCTAssertEqual(s.commit, "")
        XCTAssertEqual(s.composing, "각")
    }

    func testTextEndingOutsideHangulCommitsEverything() {
        let s = HangulPreedit.split("가ㄱ ")
        XCTAssertEqual(s.commit, "각 ")
        XCTAssertEqual(s.composing, "")
    }

    func testOnlyTheLastSyllableIsVolatile() {
        let s = HangulPreedit.split("각 까ㄲ")
        XCTAssertEqual(s.commit, "각 ")
        XCTAssertEqual(s.composing, "깎")
    }

    func testDoubleFinalIsVolatileAsOneSyllable() {
        let s = HangulPreedit.split("각 깎 다ㄹㄱ")
        XCTAssertEqual(s.commit, "각 깎 ")
        XCTAssertEqual(s.composing, "닭")
    }

    func testLatinTextHasNoComposingTail() {
        let s = HangulPreedit.split("ls -al")
        XCTAssertEqual(s.commit, "ls -al")
        XCTAssertEqual(s.composing, "")
    }

    func testEmptyDocumentSplitsIntoNothing() {
        let s = HangulPreedit.split("")
        XCTAssertEqual(s.commit, "")
        XCTAssertEqual(s.composing, "")
    }

    /// The IME rewrites `가ㄴ` into `가나` on its own; the first syllable then
    /// becomes final and only `나` stays volatile.
    func testIMEResyllabificationReleasesThePreviousSyllable() {
        XCTAssertEqual(HangulPreedit.split("가ㄴ").composing, "간")
        XCTAssertEqual(HangulPreedit.split("가ㄴ").commit, "")

        let after = HangulPreedit.split("가나")
        XCTAssertEqual(after.commit, "가")
        XCTAssertEqual(after.composing, "나")
    }

    // MARK: settle — committed text never becomes uncommitted

    func testSettleMatchesSplitWhenNothingWasSentYet() {
        let s = HangulPreedit.settle("각 까ㄲ", alreadySent: "")
        XCTAssertEqual(s.commit, "각 ")
        XCTAssertEqual(s.composing, "깎")
    }

    /// The IME starts a syllable after a space by deleting the space and the
    /// bare jamo together. Plain `split` would push 깎 back into composition
    /// and owe a DEL for it; the sent text pins it down instead.
    func testSyllableAlreadySentStaysCommittedWhenTheIMEDropsATrailingSpace() {
        let s = HangulPreedit.settle("각 까ㄲ", alreadySent: "각 깎 ")
        XCTAssertEqual(s.commit, "각 깎")
        XCTAssertEqual(s.composing, "")

        let edit = HangulPreedit.wireEdit(sent: "각 깎 ", commit: s.commit)
        XCTAssertEqual(edit.deletions, 1, "사라진 공백 하나만 지워야 한다")
        XCTAssertEqual(edit.insertion, "")
    }

    /// Real deletions still reach the wire: the document no longer starts with
    /// what was sent, so the pin does not apply.
    func testSettleStillRetractsTextTheUserActuallyDeleted() {
        let s = HangulPreedit.settle("각 ", alreadySent: "각 깎 ")
        XCTAssertEqual(s.commit, "각 ")
        XCTAssertEqual(s.composing, "")

        let edit = HangulPreedit.wireEdit(sent: "각 깎 ", commit: s.commit)
        XCTAssertEqual(edit.deletions, 2)
    }

    func testSettleNeverCommitsPastTheDocument() {
        let s = HangulPreedit.settle("가", alreadySent: "가나다")
        XCTAssertEqual(s.commit, "가")
        XCTAssertEqual(s.composing, "")
    }

    // MARK: wire diffing

    func testWireEditAppendsWhenTextGrows() {
        let edit = HangulPreedit.wireEdit(sent: "각 ", commit: "각 깎 ")
        XCTAssertEqual(edit.deletions, 0)
        XCTAssertEqual(edit.insertion, "깎 ")
    }

    func testWireEditIsEmptyWhenNothingChanged() {
        let edit = HangulPreedit.wireEdit(sent: "각 ", commit: "각 ")
        XCTAssertEqual(edit.deletions, 0)
        XCTAssertEqual(edit.insertion, "")
    }

    func testWireEditDeletesOnlyWhatDivergesFromWhatWasSent() {
        let edit = HangulPreedit.wireEdit(sent: "각 깎 ", commit: "각 ")
        XCTAssertEqual(edit.deletions, 2)
        XCTAssertEqual(edit.insertion, "")
    }

    func testWireEditReplacesTheDivergingTail() {
        let edit = HangulPreedit.wireEdit(sent: "가나다", commit: "가라")
        XCTAssertEqual(edit.deletions, 2)
        XCTAssertEqual(edit.insertion, "라")
    }
}
