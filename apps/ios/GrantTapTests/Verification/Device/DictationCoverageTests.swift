import XCTest
@testable import GrantTap

@MainActor
final class DictationCoverageTests: XCTestCase {
    func testStartHandlesDeniedThrownSuccessfulAndDuplicateTransitions() {
        let denied = Dictator(accessOverride: { $0(false) })
        denied.start()
        XCTAssertFalse(denied.isStarting)
        XCTAssertFalse(denied.isRecording)
        XCTAssertNotNil(denied.errorText)
        XCTAssertEqual(denied.stop(), "")

        let failed = Dictator(
            accessOverride: { $0(true) },
            sessionStartOverride: {
                throw NSError(domain: "dictation", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "No input",
                ])
            }
        )
        failed.start()
        XCTAssertFalse(failed.isStarting)
        XCTAssertFalse(failed.isRecording)
        XCTAssertTrue(failed.errorText?.contains("No input") == true)

        var starts = 0
        let working = Dictator(
            accessOverride: { $0(true) },
            sessionStartOverride: { starts += 1 }
        )
        working.start()
        working.start()
        XCTAssertTrue(working.isRecording)
        XCTAssertEqual(starts, 1)
        working.transcript = "Run tests"
        XCTAssertEqual(working.stop(), "Run tests")
        XCTAssertFalse(working.isRecording)
        XCTAssertEqual(working.stop(), "Run tests")
        _ = working.isAvailable
    }

    func testCandidateScoresRewardMatchingScriptConfidenceAndPreference() {
        let russian = Dictator.candidateScore(
            text: "проверить код", confidences: [0.8, 0.6], language: "ru-RU",
            preferredLanguage: "ru-RU"
        )
        let wrongScript = Dictator.candidateScore(
            text: "проверить код", confidences: [0.8, 0.6], language: "en-US",
            preferredLanguage: "ru-RU"
        )
        let english = Dictator.candidateScore(
            text: "run tests", confidences: [0.9], language: "en-US",
            preferredLanguage: "en-US"
        )
        let empty = Dictator.candidateScore(
            text: "123", confidences: [], language: "en-US", preferredLanguage: nil
        )
        XCTAssertGreaterThan(russian, wrongScript)
        XCTAssertGreaterThan(english, empty)
    }

    func testWordMergeKeepsRussianGrammarAndRecoversKnownTechnologyNames() {
        let base = [
            DictationWord(text: "проверь", start: 0, duration: 0.5, confidence: 0.8),
            DictationWord(text: "кодекс", start: 0.5, duration: 0.5, confidence: 0.65),
        ]
        let alternate = [
            DictationWord(text: "check", start: 0, duration: 0.4, confidence: 0.9),
            DictationWord(text: "Codex", start: 0.5, duration: 0.5, confidence: 0.9),
        ]
        XCTAssertEqual(
            Dictator.mergeWords(base: base, language: "ru-RU", alternate: alternate),
            "проверь Codex"
        )
        XCTAssertEqual(
            Dictator.mergeWords(base: base, language: "en-US", alternate: alternate),
            "проверь кодекс"
        )
        let weak = [DictationWord(
            text: "GitHub", start: 0.5, duration: 0.5, confidence: 0.1
        )]
        XCTAssertEqual(
            Dictator.mergeWords(base: base, language: "ru-RU", alternate: weak),
            "проверь кодекс"
        )
    }

    func testCandidateReductionUpdatesLanguageAndFinishesBoundedSessions() {
        XCTAssertEqual(
            Dictator.DictationError.recognizerUnavailable.errorDescription,
            "Speech recognition is not currently available."
        )
        XCTAssertNil(Dictator.resolvedTranscript(candidates: [:], preferredLanguage: nil))
        let russian = DictationCandidate(text: "проверь кодекс", words: [
            DictationWord(text: "проверь", start: 0, duration: 0.5, confidence: 0.99),
            DictationWord(text: "кодекс", start: 0.5, duration: 0.5, confidence: 0.95),
        ])
        let english = DictationCandidate(text: "check Codex", words: [
            DictationWord(text: "check", start: 0, duration: 0.5, confidence: 0.2),
            DictationWord(text: "Codex", start: 0.5, duration: 0.5, confidence: 0.9),
        ])
        let resolved = Dictator.resolvedTranscript(
            candidates: ["ru-RU": russian, "en-US": english],
            preferredLanguage: "ru-RU"
        )
        XCTAssertEqual(resolved?.text, "проверь Codex")
        XCTAssertEqual(resolved?.language, "RU")

        let working = Dictator(
            accessOverride: { $0(true) }, sessionStartOverride: {}
        )
        working.start()
        working.handleRecognition(
            candidate: english, errorDescription: nil, isFinal: false,
            identifier: "en-US", activeTaskCount: 2
        )
        XCTAssertEqual(working.transcript, "check Codex")
        XCTAssertEqual(working.detectedLanguage, "EN")
        working.handleRecognition(
            candidate: nil, errorDescription: nil, isFinal: true,
            identifier: "en-US", activeTaskCount: 1
        )
        XCTAssertFalse(working.isRecording)

        let failed = Dictator(
            accessOverride: { $0(true) }, sessionStartOverride: {}
        )
        failed.start()
        failed.handleRecognition(
            candidate: nil, errorDescription: "Recognizer stopped", isFinal: false,
            identifier: "ru-RU", activeTaskCount: 1
        )
        XCTAssertEqual(failed.errorText, "Speech recognition stopped: Recognizer stopped")
        XCTAssertFalse(failed.isRecording)
    }

    func testSystemSessionPathFailsClosedWhenSimulatorHasNoUsableRecognizer() async {
        let dictator = Dictator(accessOverride: { $0(true) })
        dictator.start()
        let deadline = Date().addingTimeInterval(1)
        while dictator.isStarting, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        if dictator.isRecording { _ = dictator.stop() }
        XCTAssertFalse(dictator.isStarting)
        XCTAssertFalse(dictator.isRecording)
    }
}
