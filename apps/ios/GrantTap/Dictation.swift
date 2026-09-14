import Foundation
import Speech
import AVFoundation

struct DictationWord: Equatable {
    let text: String
    let start: TimeInterval
    let duration: TimeInterval
    let confidence: Float
}

struct DictationCandidate: Equatable {
    let text: String
    let words: [DictationWord]
}

/// Privacy-first dictation. Streams the microphone through SFSpeechRecognizer
/// and publishes the transcript as it grows, so a mic button can show words
/// appearing and hand the final text to the app.
///
/// Each locale stays on-device whenever Apple supports it. If a requested
/// locale has no on-device recognizer, at most one Apple server recognition
/// stream is used as a fallback. The app never stores the captured audio.
@MainActor
final class Dictator: ObservableObject {
    @Published var isRecording = false
    @Published var isStarting = false
    @Published var transcript = ""
    @Published var errorText: String?
    @Published var detectedLanguage: String?

    private var languageIdentifiers: [String] {
        AppLocale.code == "ru" ? ["ru-RU", "en-US"] : ["en-US", "ru-RU"]
    }
    private let engine = AVAudioEngine()
    private var requests: [String: SFSpeechAudioBufferRecognitionRequest] = [:]
    private var tasks: [String: SFSpeechRecognitionTask] = [:]
    private var candidates: [String: DictationCandidate] = [:]
    private var stoppedLanguages = Set<String>()
    private let accessOverride: ((@escaping (Bool) -> Void) -> Void)?
    private let sessionStartOverride: (() throws -> Void)?
    private var overrideSessionActive = false

    init(
        accessOverride: ((@escaping (Bool) -> Void) -> Void)? = nil,
        sessionStartOverride: (() throws -> Void)? = nil
    ) {
        self.accessOverride = accessOverride
        self.sessionStartOverride = sessionStartOverride
    }

    enum DictationError: LocalizedError {
        case recognizerUnavailable

        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable:
                return L("Speech recognition is not currently available.")
            }
        }
    }

    var isAvailable: Bool {
        languageIdentifiers.contains {
            SFSpeechRecognizer(locale: Locale(identifier: $0))?.isAvailable ?? false
        }
    }

    /// Ask once; the callback says whether we may record.
    func requestAccess(_ done: @escaping (Bool) -> Void) {
        if let accessOverride {
            accessOverride(done)
            return
        }
        SFSpeechRecognizer.requestAuthorization { auth in
            guard auth == .authorized else { DispatchQueue.main.async { done(false) }; return }
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async { done(granted) }
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    DispatchQueue.main.async { done(granted) }
                }
            }
        }
    }

    func start() {
        guard !isRecording, !isStarting else { return }
        errorText = nil
        transcript = ""
        detectedLanguage = nil
        isStarting = true

        requestAccess { [weak self] ok in
            guard let self else { return }
            guard ok else {
                self.isStarting = false
                self.errorText = L("Microphone or speech-recognition access was not granted.")
                return
            }
            do {
                if let sessionStartOverride = self.sessionStartOverride {
                    try sessionStartOverride()
                    self.isStarting = false
                    self.isRecording = true
                    self.overrideSessionActive = true
                } else {
                    try self.beginSession()
                }
            } catch {
                self.isStarting = false
                self.errorText = String(
                    format: L("Recording could not start: %@"),
                    error.localizedDescription
                )
            }
        }
    }

    private func beginSession() throws {
        let availableRecognizers = languageIdentifiers.compactMap { identifier -> (String, SFSpeechRecognizer)? in
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)),
                  recognizer.isAvailable else { return nil }
            return (identifier, recognizer)
        }
        // Parallel RU/EN candidates make mixed technical dictation useful, but
        // two network recognizers would upload the same microphone stream
        // twice. Keep every on-device candidate and no more than one server
        // fallback, in the user's preferred-language order.
        let localRecognizers = availableRecognizers.filter { $0.1.supportsOnDeviceRecognition }
        let serverFallback = availableRecognizers.first { !$0.1.supportsOnDeviceRecognition }
        let recognizers = localRecognizers + (serverFallback.map { [$0] } ?? [])
        guard !recognizers.isEmpty else {
            throw DictationError.recognizerUnavailable
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        candidates = [:]
        stoppedLanguages = []
        requests = Dictionary(uniqueKeysWithValues: recognizers.map { identifier, recognizer in
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            request.taskHint = .dictation
            request.contextualStrings = VoiceTextNormalizer.recognitionTerms
            return (identifier, request)
        })

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let activeRequests = Array(requests.values)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            for request in activeRequests { request.append(buffer) }
        }

        engine.prepare()
        try engine.start()
        isStarting = false
        isRecording = true

        for (identifier, recognizer) in recognizers {
            guard let request = requests[identifier] else { continue }
            tasks[identifier] = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    self.handleRecognition(
                        candidate: result.map { Self.candidate($0.bestTranscription) },
                        errorDescription: error?.localizedDescription,
                        isFinal: result?.isFinal == true, identifier: identifier,
                        activeTaskCount: self.tasks.count
                    )
                }
            }
        }
    }

    /// Stop and return the final transcript.
    @discardableResult
    func stop() -> String {
        finish()
        return transcript
    }

    private func finish() {
        isStarting = false
        guard isRecording else { return }
        isRecording = false
        if overrideSessionActive {
            overrideSessionActive = false
            return
        }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        for request in requests.values { request.endAudio() }
        for task in tasks.values { task.cancel() }
        requests = [:]
        tasks = [:]
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func updateTranscript() {
        guard let result = Self.resolvedTranscript(
            candidates: candidates, preferredLanguage: languageIdentifiers.first
        ) else { return }
        transcript = result.text
        detectedLanguage = result.language
    }

    func handleRecognition(
        candidate: DictationCandidate?, errorDescription: String?, isFinal: Bool,
        identifier: String, activeTaskCount: Int
    ) {
        if let candidate {
            candidates[identifier] = candidate
            updateTranscript()
        }
        if errorDescription != nil || isFinal { stoppedLanguages.insert(identifier) }
        guard isRecording, stoppedLanguages.count == activeTaskCount else { return }
        if candidates.isEmpty, let errorDescription {
            errorText = String(
                format: L("Speech recognition stopped: %@"), errorDescription
            )
        }
        finish()
    }

    private static func candidate(_ transcription: SFTranscription) -> DictationCandidate {
        DictationCandidate(
            text: transcription.formattedString,
            words: transcription.segments.map {
                DictationWord(
                    text: $0.substring, start: $0.timestamp,
                    duration: $0.duration, confidence: $0.confidence
                )
            }
        )
    }
}
