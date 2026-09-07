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

    // MARK: removeLastJamo

    func testRemoveLastJamo_겹받침이_있는_음절_종성_하나만_제거() {
        XCTAssertEqual(HangulComposition.removeLastJamo("닭"), "달")
    }

    func testRemoveLastJamo_홑받침_제거() {
        XCTAssertEqual(HangulComposition.removeLastJamo("각"), "가")
    }

    func testRemoveLastJamo_복모음_첫_모음만_남기기() {
        XCTAssertEqual(HangulComposition.removeLastJamo("와"), "오")
    }

    func testRemoveLastJamo_단모음_초성_반환() {
        XCTAssertEqual(HangulComposition.removeLastJamo("가"), "ㄱ")
    }

    func testRemoveLastJamo_자음_낱자_삭제() {
        XCTAssertEqual(HangulComposition.removeLastJamo("ㄱ"), "")
    }

    func testRemoveLastJamo_모음_낱자_삭제() {
        XCTAssertEqual(HangulComposition.removeLastJamo("ㅏ"), "")
    }

    func testRemoveLastJamo_한글아니면_nil_반환() {
        XCTAssertEqual(HangulComposition.removeLastJamo("a"), nil)
    }

    // MARK: backspace — 조합 중(아직 아무것도 안 보낸 경우, alreadySent: "")

    func testBackspace_조합중_자모_단위() {
        XCTAssertEqual(HangulPreedit.backspace("가ㄱ", alreadySent: ""), "가")
        XCTAssertEqual(HangulPreedit.backspace("가", alreadySent: ""), "ㄱ")
        XCTAssertEqual(HangulPreedit.backspace("ㄱ", alreadySent: ""), "")
        XCTAssertEqual(HangulPreedit.backspace("다ㄹㄱ", alreadySent: ""), "다ㄹ")
        XCTAssertEqual(HangulPreedit.backspace("와", alreadySent: ""), "오")
    }

    // MARK: backspace — 확정분(이미 전송된 경우)

    func testBackspace_확정분_통글자_지우기() {
        XCTAssertEqual(HangulPreedit.backspace("각 깎", alreadySent: "각 깎"), "각 ")
        XCTAssertEqual(HangulPreedit.backspace("안녕", alreadySent: "안녕"), "안")
    }

    // MARK: backspace — 확정분 마지막 글자 삭제 회귀

    func testBackspaceOnTheLastRemainingCommittedCharacterEmptiesTheDocument() {
        XCTAssertEqual(HangulPreedit.backspace("안", alreadySent: "안"), "")
        XCTAssertEqual(HangulPreedit.backspace("a", alreadySent: "a"), "")
    }

func testBackspaceOnSettledTextKeepsAllJamoThatFormTheRemovedSyllable() {
    // "가ㄱ 까ㄲ 다ㄹㄱ 가ㅂㅅ " composes to "각 깎 닭 값 " (already fully sent).
    // Removing the trailing space must leave "각 깎 닭 값" intact — the
    // 값 syllable (built from 가+ㅂ+ㅅ) must not lose its batchim.
    let storage = "가ㄱ 까ㄲ 다ㄹㄱ 가ㅂㅅ "
    let sent = HangulPreedit.composeDocument(storage)
    let after = HangulPreedit.backspace(storage, alreadySent: sent)
    XCTAssertEqual(HangulPreedit.composeDocument(after), "각 깎 닭 값")
}

// MARK: backspace — 영문 회귀

func testBackspace_영문_한_글자_지우기() {
    XCTAssertEqual(HangulPreedit.backspace("abc", alreadySent: "abc"), "ab")
}
}
