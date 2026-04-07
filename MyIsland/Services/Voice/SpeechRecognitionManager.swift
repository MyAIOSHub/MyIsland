import Speech
import AVFoundation
import Combine

@MainActor
final class VoiceSpeechManager: ObservableObject {
    @Published private(set) var partialText: String = ""
    @Published private(set) var finalText: String?
    @Published private(set) var isRecognizing: Bool = false

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var locale: Locale = Locale(identifier: "zh-Hans") {
        didSet {
            recognizer = SFSpeechRecognizer(locale: locale)
        }
    }

    init() {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    func startStreaming() {
        guard let recognizer, recognizer.isAvailable else {
            finalText = nil
            return
        }

        partialText = ""
        finalText = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.partialText = text
                    if result.isFinal {
                        print("[Voice] Speech final result: '\(text)'")
                        self.finalText = text
                        self.isRecognizing = false
                    }
                }
                if let error {
                    print("[Voice] Speech error: \(error.localizedDescription)")
                    if self.finalText == nil {
                        if !self.partialText.isEmpty {
                            print("[Voice] Using partial text as final: '\(self.partialText)'")
                            self.finalText = self.partialText
                        } else {
                            print("[Voice] Speech error with no text available")
                        }
                        self.isRecognizing = false
                    }
                }
            }
        }

        isRecognizing = true
    }

    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    func stopStreaming() {
        request?.endAudio()
    }

    func cancel() {
        task?.cancel()
        task = nil
        request = nil
        isRecognizing = false
        partialText = ""
        finalText = nil
    }
}
