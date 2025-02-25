import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import AppKit
import KeyboardShortcuts
import os

enum WhisperStateError: Error, Identifiable {
    case modelLoadFailed
    case transcriptionFailed
    case recordingFailed
    case accessibilityPermissionDenied
    case modelDownloadFailed
    case modelDeletionFailed
    case unknownError
    
    var id: String { UUID().uuidString }
}

extension WhisperStateError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .modelLoadFailed:
            return "Failed to load the transcription model."
        case .transcriptionFailed:
            return "Failed to transcribe the audio."
        case .recordingFailed:
            return "Failed to start or stop recording."
        case .accessibilityPermissionDenied:
            return "Accessibility permission is required for automatic pasting."
        case .modelDownloadFailed:
            return "Failed to download the model."
        case .modelDeletionFailed:
            return "Failed to delete the model."
        case .unknownError:
            return "An unknown error occurred."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .modelLoadFailed:
            return "Try selecting a different model or redownloading the current model."
        case .transcriptionFailed:
            return "Check your audio input and try again. If the problem persists, try a different model."
        case .recordingFailed:
            return "Check your microphone permissions and try again."
        case .accessibilityPermissionDenied:
            return "Go to System Preferences > Security & Privacy > Privacy > Accessibility and allow VoiceInk."
        case .modelDownloadFailed:
            return "Check your internet connection and try again. If the problem persists, try a different model."
        case .modelDeletionFailed:
            return "Restart the application and try again. If the problem persists, you may need to manually delete the model file."
        case .unknownError:
            return "Please restart the application. If the problem persists, contact support."
        }
    }
}

@MainActor
class WhisperState: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isModelLoaded = false
    @Published var messageLog = ""
    @Published var canTranscribe = false
    @Published var isRecording = false
    @Published var currentModel: WhisperModel?
    @Published var isModelLoading = false
    @Published var availableModels: [WhisperModel] = []
    @Published var predefinedModels: [PredefinedModel] = PredefinedModels.models
    @Published var clipboardMessage = ""
    @Published var miniRecorderError: String?
    @Published var isProcessing = false
    @Published var shouldCancelRecording = false
    @Published var isTranscribing = false
    @Published var transcriptionPrompt: String = UserDefaults.standard.string(forKey: "TranscriptionPrompt") ?? ""
    @Published var isAutoCopyEnabled: Bool = UserDefaults.standard.object(forKey: "IsAutoCopyEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isAutoCopyEnabled, forKey: "IsAutoCopyEnabled")
        }
    }
    @Published var recorderType: String = UserDefaults.standard.string(forKey: "RecorderType") ?? "mini" {
        didSet {
            UserDefaults.standard.set(recorderType, forKey: "RecorderType")
        }
    }
    
    private var whisperContext: WhisperContext?
    private let recorder = Recorder()
    private var recordedFile: URL? = nil
    private var dictionaryWords: [String] = []
    private let saveKey = "CustomDictionaryItems"
    
    let modelContext: ModelContext
    
    private let basePrompt = """
    Hey, How are you doing? Are you good? It's nice to meet after so long.
    
    """
    

    private var modelUrl: URL? {
        let possibleURLs = [
            Bundle.main.url(forResource: "ggml-base.en", withExtension: "bin", subdirectory: "Models"),
            Bundle.main.url(forResource: "ggml-base.en", withExtension: "bin"),
            Bundle.main.bundleURL.appendingPathComponent("Models/ggml-base.en.bin")
        ]
        
        for url in possibleURLs {
            if let url = url, FileManager.default.fileExists(atPath: url.path) {
                print("Model found at: \(url.path)")
                return url
            }
        }
        
        print("Model not found in any of the expected locations")
        return nil
    }
    
    private enum LoadError: Error {
        case couldNotLocateModel
    }
    
    private let modelsDirectory: URL
    private let recordingsDirectory: URL
    private var transcriptionStartTime: Date?
    
    private var enhancementService: AIEnhancementService?
    
    private let licenseViewModel: LicenseViewModel
    
    private var notchWindowManager: NotchWindowManager?
    private var miniWindowManager: MiniWindowManager?
    var audioEngine: AudioEngine
    
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "WhisperState")
    
    init(modelContext: ModelContext, enhancementService: AIEnhancementService? = nil) {
        self.modelContext = modelContext
        self.modelsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("WhisperModels")
        self.recordingsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk")
            .appendingPathComponent("Recordings")
        self.audioEngine = AudioEngine()
        self.enhancementService = enhancementService
        self.licenseViewModel = LicenseViewModel()
        
        super.init()
        
        setupNotifications()
        createModelsDirectoryIfNeeded()
        createRecordingsDirectoryIfNeeded()
        loadAvailableModels()
        loadDictionaryItems()
        
        // Load saved model
        if let savedModelName = UserDefaults.standard.string(forKey: "CurrentModel"),
           let savedModel = availableModels.first(where: { $0.name == savedModelName }) {
            currentModel = savedModel
            print("Initialized with model: \(savedModel.name)")
        }
        
        updateTranscriptionPrompt()
    }
    
    private func createModelsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true, attributes: nil)
            print("📂 Models directory created/exists at: \(modelsDirectory.path)")
        } catch {
            print("Error creating models directory: \(error.localizedDescription)")
        }
    }
    
    private func createRecordingsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true, attributes: nil)
            logger.info("📂 Recordings directory created/exists at: \(self.recordingsDirectory.path)")
        } catch {
            logger.error("Error creating recordings directory: \(error.localizedDescription)")
        }
    }
    
    private func loadAvailableModels() {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil)
            print("📂 Loading models from directory: \(modelsDirectory.path)")
            print("📝 Found models: \(fileURLs.map { $0.lastPathComponent }.joined(separator: ", "))")
            availableModels = fileURLs.compactMap { url in
                guard url.pathExtension == "bin" else { return nil }
                return WhisperModel(name: url.deletingPathExtension().lastPathComponent, url: url)
            }
        } catch {
            print("Error loading available models: \(error.localizedDescription)")
        }
    }
    
    private func loadDictionaryItems() {
        guard let data = UserDefaults.standard.data(forKey: saveKey) else { return }
        
        // Try loading with new format first
        if let savedItems = try? JSONDecoder().decode([DictionaryItem].self, from: data) {
            let enabledWords = savedItems.filter { $0.isEnabled }.map { $0.word }
            dictionaryWords = enabledWords
            updateTranscriptionPrompt()
        }
    }
    
    // Modify loadModel to be private and async
    private func loadModel(_ model: WhisperModel) async throws {
        guard whisperContext == nil else { return } // Model already loaded
        
        isModelLoading = true
        defer { isModelLoading = false }
        
        messageLog += "Loading model...\n"
        print("Attempting to load model from: \(model.url.path)")
        do {
            whisperContext = try await WhisperContext.createContext(path: model.url.path)
            isModelLoaded = true
            currentModel = model
            print("Model loaded: \(model.name)")
            messageLog += "Loaded model \(model.name)\n"
        } catch {
            print("Error loading model: \(error.localizedDescription)")
            throw WhisperStateError.modelLoadFailed
        }
    }
    
    func setDefaultModel(_ model: WhisperModel) async {
        do {
            currentModel = model
            UserDefaults.standard.set(model.name, forKey: "CurrentModel")
            canTranscribe = true
            print("Model set: \(model.name)")
        } catch {
            currentError = error as? WhisperStateError ?? .unknownError
            print("Error setting default model: \(error.localizedDescription)")
            messageLog += "Error setting default model: \(error.localizedDescription)\n"
            canTranscribe = false
        }
    }

    func toggleRecord() async {
        if isRecording {
            logger.info("Stopping recording")
            await recorder.stopRecording()
            isRecording = false
            isVisualizerActive = false
            audioEngine.stopAudioEngine()
            if let recordedFile {
                let duration = Date().timeIntervalSince(transcriptionStartTime ?? Date())
                logger.info("Recording stopped, duration: \(duration)s")
                await transcribeAudio(recordedFile, duration: duration)
            } else {
                logger.warning("No recorded file found after stopping recording")
            }
        } else {
            logger.info("Starting recording process")
            requestRecordPermission { [self] granted in
                if granted {
                    logger.info("Recording permission granted")
                    Task {
                        do {
                            // Create output file first
                            let file = try FileManager.default.url(for: .documentDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: true)
                                .appending(path: "output.wav")
                            self.logger.info("Created output file at: \(file.path)")
                            
                            // Only start the audio engine if it's not already running
                            // (it might have been started in parallel by handleToggleMiniRecorder)
                            if !self.audioEngine.isRunning {
                                self.logger.info("Starting audio engine")
                                self.audioEngine.startAudioEngine()
                            } else {
                                self.logger.info("Audio engine already running")
                            }
                            
                            self.logger.info("Initializing recorder")
                            try await self.recorder.startRecording(toOutputFile: file, delegate: self)
                            
                            self.logger.info("Recording started successfully")
                            self.isRecording = true
                            self.isVisualizerActive = true
                            self.recordedFile = file
                            self.transcriptionStartTime = Date()
                            
                            // Handle tasks sequentially
                            // Step 1: Apply power mode configuration
                            await ActiveWindowService.shared.applyConfigurationForCurrentApp()
                            
                            // Step 2: Handle screen capture if enabled by the configuration
                            if let enhancementService = self.enhancementService,
                               enhancementService.isEnhancementEnabled &&
                               enhancementService.useScreenCaptureContext {
                                await MainActor.run {
                                    self.messageLog += "Capturing screen context...\n"
                                }
                                await enhancementService.captureScreenContext()
                            }
                            
                            // Step 3: Load model if needed
                            if let currentModel = self.currentModel, self.whisperContext == nil {
                                do {
                                    try await self.loadModel(currentModel)
                                } catch {
                                    await MainActor.run {
                                        print("Error preloading model: \(error.localizedDescription)")
                                        self.messageLog += "Error preloading model: \(error.localizedDescription)\n"
                                    }
                                }
                            }
                        } catch {
                            self.logger.error("Failed to start recording: \(error.localizedDescription)")
                            print(error.localizedDescription)
                            self.messageLog += "\(error.localizedDescription)\n"
                            self.isRecording = false
                            self.isVisualizerActive = false
                            self.audioEngine.stopAudioEngine()
                        }
                    }
                } else {
                    self.logger.error("Recording permission denied")
                    self.messageLog += "Recording permission denied\n"
                }
            }
        }
    }
    
    private func requestRecordPermission(response: @escaping (Bool) -> Void) {
#if os(macOS)
        response(true)
#else
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            response(granted)
        }
#endif
    }
    
    // MARK: AVAudioRecorderDelegate
    
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error {
            Task {
                await handleRecError(error)
            }
        }
    }
    
    private func handleRecError(_ error: Error) {
        logger.error("Recording error occurred: \(error.localizedDescription)")
        print(error.localizedDescription)
        messageLog += "\(error.localizedDescription)\n"
        isRecording = false
    }
    
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task {
            await onDidFinishRecording(success: flag)
        }
    }
    
    private func onDidFinishRecording(success: Bool) {
        if success {
            logger.info("Recording finished successfully")
        } else {
            logger.error("Recording finished unsuccessfully")
        }
        isRecording = false
    }
    
    @Published var downloadProgress: [String: Double] = [:]

    func downloadModel(_ model: PredefinedModel) async {
        guard let url = URL(string: model.downloadURL) else {
            print("Invalid URL for model: \(model.name)")
            return
        }

        print("Starting download for model: \(model.name)")

        do {
            let (data, response) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
                let task = URLSession.shared.dataTask(with: url) { data, response, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode),
                          let data = data else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                        return
                    }
                    continuation.resume(returning: (data, httpResponse))
                }
                
                task.resume()
                
                // Set up progress observation
                let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                    DispatchQueue.main.async {
                        self.downloadProgress[model.name] = progress.fractionCompleted
                    }
                }
                
                // Store the observation to keep it alive
                Task {
                    await withTaskCancellationHandler {
                        observation.invalidate()
                    } operation: {
                        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in
                            // This continuation is immediately resumed by the TaskDelegate
                        }
                    }
                }
            }

            let destinationURL = modelsDirectory.appendingPathComponent(model.filename)
            try data.write(to: destinationURL)

            availableModels.append(WhisperModel(name: model.name, url: destinationURL))
            print("Download completed for model: \(model.name)")
            
            // Remove the progress entry when download is complete
            self.downloadProgress.removeValue(forKey: model.name)
        } catch {
            print("Error downloading model \(model.name): \(error.localizedDescription)")
            currentError = .modelDownloadFailed
            self.downloadProgress.removeValue(forKey: model.name)
        }
    }

    // Update transcribeAudio to use the preloaded model
    private func transcribeAudio(_ url: URL, duration: TimeInterval) async {
        if shouldCancelRecording {
            return
        }

        guard let currentModel = currentModel else {
            messageLog += "Cannot transcribe: No model selected.\n"
            currentError = .modelLoadFailed
            return
        }

        guard let whisperContext = whisperContext else {
            messageLog += "Cannot transcribe: Model not loaded.\n"
            currentError = .modelLoadFailed
            return
        }

        do {
            isProcessing = true
            isTranscribing = true
            canTranscribe = false

            // Save the recording permanently first
            let permanentURL = try saveRecordingPermanently(url)
            let permanentURLString = permanentURL.absoluteString

            // Check cancellation after setting processing state
            if shouldCancelRecording {
                await cleanupResources()
                return
            }

            messageLog += "Reading wave samples...\n"
            let data = try readAudioSamples(url)
            
            // Check cancellation after reading samples
            if shouldCancelRecording {
                await cleanupResources()
                return
            }
            
            messageLog += "Transcribing data using \(currentModel.name) model...\n"
            
            // Set prompt before transcription
            messageLog += "Setting prompt: \(transcriptionPrompt)\n"
            await whisperContext.setPrompt(transcriptionPrompt)
            
            // Check cancellation before starting transcription
            if shouldCancelRecording {
                await cleanupResources()
                return
            }
            
            await whisperContext.fullTranscribe(samples: data)
            
            // Check cancellation after transcription but before enhancement
            if shouldCancelRecording {
                await cleanupResources()
                return
            }
            
            var text = await whisperContext.getTranscription()
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Try to enhance the transcription if the service is available and enabled
            if let enhancementService = enhancementService,
               enhancementService.isEnhancementEnabled,
               enhancementService.isConfigured {
                do {
                    // Check cancellation before enhancement
                    if shouldCancelRecording {
                        await cleanupResources()
                        return
                    }
                    
                    messageLog += "Enhancing transcription with AI...\n"
                    let enhancedText = try await enhancementService.enhance(text)
                    messageLog += "Enhancement completed.\n"
                    
                    // Create transcription with both original and enhanced text, plus audio URL
                    let newTranscription = Transcription(
                        text: text,
                        duration: duration,
                        enhancedText: enhancedText,
                        audioFileURL: permanentURLString
                    )
                    modelContext.insert(newTranscription)
                    try? modelContext.save()
                    
                    // Use enhanced text for clipboard and pasting
                    text = enhancedText
                } catch {
                    messageLog += "Enhancement failed: \(error.localizedDescription). Using original transcription.\n"
                    // Create transcription with only original text if enhancement fails
                    let newTranscription = Transcription(
                        text: text,
                        duration: duration,
                        audioFileURL: permanentURLString
                    )
                    modelContext.insert(newTranscription)
                    try? modelContext.save()
                }
            } else {
                // Create transcription with only original text if enhancement is not enabled
                let newTranscription = Transcription(
                    text: text,
                    duration: duration,
                    audioFileURL: permanentURLString
                )
                modelContext.insert(newTranscription)
                try? modelContext.save()
            }
            
            // Add upgrade message if trial has expired
            if case .trialExpired = licenseViewModel.licenseState {
                text = """
                    Your trial has expired. Upgrade to VoiceInk Pro at tryvoiceink.com/buy
                    
                    \(text)
                    """
            }
            
            messageLog += "Done: \(text)\n"
            
            // Play stop sound when transcription is complete
            SoundManager.shared.playStopSound()
            
            if isAutoCopyEnabled {
                ClipboardManager.copyToClipboard(text)
                clipboardMessage = "Transcription copied to clipboard"
            }
            
            if AXIsProcessTrusted() {
                // For notch recorder, paste right after animation starts (animation takes 0.3s)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    CursorPaster.pasteAtCursor(text)
                }
            } else {
                messageLog += "Accessibility permissions not granted. Transcription not pasted automatically.\n"
            }
            
            Task {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                clipboardMessage = ""
            }
            
            await cleanupResources()
            
            // Don't set processing states to false here
            // Let dismissMiniRecorder handle it
            await dismissMiniRecorder()
            
        } catch {
            print(error.localizedDescription)
            messageLog += "\(error.localizedDescription)\n"
            currentError = .transcriptionFailed
            
            await cleanupResources()
            // Even in error case, let dismissMiniRecorder handle the states
            await dismissMiniRecorder()
        }
    }

    private func readAudioSamples(_ url: URL) throws -> [Float] {
        return try decodeWaveFile(url)
    }

    private func decodeWaveFile(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        let floats = stride(from: 44, to: data.count, by: 2).map {
            return data[$0..<$0 + 2].withUnsafeBytes {
                let short = Int16(littleEndian: $0.load(as: Int16.self))
                return max(-1.0, min(Float(short) / 32767.0, 1.0))
            }
        }
        return floats
    }

    func deleteModel(_ model: WhisperModel) async {
        do {
            try FileManager.default.removeItem(at: model.url)
            availableModels.removeAll { $0.id == model.id }
            if currentModel?.id == model.id {
                currentModel = nil
                canTranscribe = false
            }
        } catch {
            print("Error deleting model: \(error.localizedDescription)")
            messageLog += "Error deleting model: \(error.localizedDescription)\n"
            currentError = .modelDeletionFailed
        }
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    @Published var isVisualizerActive = false
    
    @Published var isMiniRecorderVisible = false {
        didSet {
            if isMiniRecorderVisible {
                showRecorderPanel()
            } else {
                hideRecorderPanel()
            }
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleToggleMiniRecorder), name: .toggleMiniRecorder, object: nil)
    }
    
    @objc public func handleToggleMiniRecorder() {
        if isMiniRecorderVisible {
            // If the recorder is visible, toggle recording
            Task {
                await toggleRecord()
            }
        } else {
            // Start a parallel task for both UI and recording
            Task {
                // Play start sound first
                SoundManager.shared.playStartSound()
                
                // Start audio engine immediately - this can happen in parallel
                audioEngine.startAudioEngine()
                
                // Show UI (this is quick now that we removed animations)
                await MainActor.run {
                    showRecorderPanel() // Modified version that doesn't start audio engine
                    isMiniRecorderVisible = true
                }
                
                // Start recording (this will happen in parallel with UI showing)
                await toggleRecord()
            }
        }
    }

    private func showRecorderPanel() {
        logger.info("Showing recorder panel, type: \(self.recorderType)")
        if recorderType == "notch" {
            if notchWindowManager == nil {
                notchWindowManager = NotchWindowManager(whisperState: self, audioEngine: audioEngine)
                logger.info("Created new notch window manager")
            }
            notchWindowManager?.show()
        } else {
            if miniWindowManager == nil {
                miniWindowManager = MiniWindowManager(whisperState: self, audioEngine: audioEngine)
                logger.info("Created new mini window manager")
            }
            miniWindowManager?.show()
        }
        // Audio engine is now started separately in handleToggleMiniRecorder
        // SoundManager.shared.playStartSound() - Moved to handleToggleMiniRecorder
        logger.info("Recorder panel shown successfully")
    }

    private func hideRecorderPanel() {
        logger.info("Hiding recorder panel")
        audioEngine.stopAudioEngine()
        
        if isRecording {
            logger.info("Recording still active, stopping before hiding")
            Task {
                await toggleRecord()
            }
        }
        logger.info("Recorder panel hidden")
    }

    func toggleMiniRecorder() async {
        if isMiniRecorderVisible {
            await dismissMiniRecorder()
        } else {
            // Start a parallel task for both UI and recording
            Task {
                // Play start sound first
                SoundManager.shared.playStartSound()
                
                // Start audio engine immediately - this can happen in parallel
                audioEngine.startAudioEngine()
                
                // Show UI (this is quick now that we removed animations)
                await MainActor.run {
                    showRecorderPanel() // Modified version that doesn't start audio engine
                    isMiniRecorderVisible = true
                }
                
                // Start recording
                await toggleRecord()
            }
        }
    }

    private func cleanupResources() async {
        // Only cleanup temporary files, not the permanent recordings
        audioEngine.stopAudioEngine()
        
        // Release whisper resources if not needed
        if !isRecording && !isProcessing {
            await whisperContext?.releaseResources()
            whisperContext = nil
            isModelLoaded = false
        }
    }

    func dismissMiniRecorder() async {
        logger.info("Starting mini recorder dismissal")
        // 1. Cancel any ongoing recording
        shouldCancelRecording = true
        if isRecording {
            logger.info("Stopping active recording")
            await recorder.stopRecording()
        }
        
        // 2. Start dismissal animation while keeping processing state
        logger.info("Starting dismissal animation")
        if recorderType == "notch" {
            notchWindowManager?.hide()
        } else {
            miniWindowManager?.hide()
        }
        
        // 3. No need to wait for animation since we removed it
        // try? await Task.sleep(nanoseconds: 700_000_000)  // 0.7 seconds
        
        // 4. Clean up states immediately
        await MainActor.run {
            logger.info("Cleaning up recorder states")
            // Reset all states
            isRecording = false
            isVisualizerActive = false
            isProcessing = false
            isTranscribing = false
            canTranscribe = true
            isMiniRecorderVisible = false
            shouldCancelRecording = false
        }
        
        // 5. Finally clean up resources
        logger.info("Cleaning up resources")
        await cleanupResources()
        logger.info("Mini recorder dismissal completed")
    }

    func cancelRecording() async {
        shouldCancelRecording = true
        SoundManager.shared.playEscSound()
        if isRecording {
            await recorder.stopRecording()
        }
        await dismissMiniRecorder()
    }

    @Published var currentError: WhisperStateError?

    // Replace the existing unloadModel function with this one
    func unloadModel() {
        Task {
            await whisperContext?.releaseResources()
            whisperContext = nil
            isModelLoaded = false
            
            // Additional cleanup
            audioEngine.stopAudioEngine()
            if let recordedFile = recordedFile {
                try? FileManager.default.removeItem(at: recordedFile)
                self.recordedFile = nil
            }
        }
    }

    

    // Optional: Method to clear downloaded models
    private func clearDownloadedModels() async {
        for model in availableModels {
            do {
                try FileManager.default.removeItem(at: model.url)
            } catch {
                print("Error deleting model file: \(error.localizedDescription)")
            }
        }
        availableModels.removeAll()
    }

    // Keep only these essential prompt-related methods
    func updateDictionaryWords(_ words: [String]) {
        dictionaryWords = words
        updateTranscriptionPrompt()
    }
    
    private func updateTranscriptionPrompt() {
        var prompt = basePrompt
        
        // Combine permanent words with user-added dictionary words
        var allWords = ["VoiceInk"]  // Add VoiceInk as permanent word
        allWords.append(contentsOf: dictionaryWords)
        
        if !allWords.isEmpty {
            prompt += "\nImportant words: " + allWords.joined(separator: ", ")
        }
        
        transcriptionPrompt = prompt
        UserDefaults.standard.set(prompt, forKey: "TranscriptionPrompt")
        
        // Update whisper context if it exists
        if let whisperContext = whisperContext {
            Task {
                await whisperContext.setPrompt(prompt)
            }
        }
    }

    // Public method to access enhancement service
    func getEnhancementService() -> AIEnhancementService? {
        return enhancementService
    }

    private func saveRecordingPermanently(_ tempURL: URL) throws -> URL {
        let fileName = "\(UUID().uuidString).wav"
        let permanentURL = recordingsDirectory.appendingPathComponent(fileName)
        
        try FileManager.default.copyItem(at: tempURL, to: permanentURL)
        logger.info("Saved recording permanently at: \(permanentURL.path)")
        
        return permanentURL
    }

    func saveDictionaryItems(_ items: [DictionaryItem]) async {
        if let encoded = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
            let enabledWords = items.filter { $0.isEnabled }.map { $0.word }
            dictionaryWords = enabledWords
            updateTranscriptionPrompt()
        }
    }
}

struct WhisperModel: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    var downloadURL: String {
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)"
    }
    var filename: String {
        "\(name).bin"
    }
}

// Helper class for task delegation
private class TaskDelegate: NSObject, URLSessionTaskDelegate {
    private let continuation: CheckedContinuation<Void, Never>
    
    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        continuation.resume()
    }
}

extension Notification.Name {
    static let toggleMiniRecorder = Notification.Name("toggleMiniRecorder")
}

