import Foundation
#if canImport(whisper)
import whisper
#else
#error("Unable to import whisper module. Please check your project configuration.")
#endif

enum WhisperError: Error {
    case couldNotInitializeContext
}

// Meet Whisper C++ constraint: Don't access from more than one thread at a time.
actor WhisperContext {
    private var context: OpaquePointer?
    private var languageCString: [CChar]?
    private var prompt: String?
    private var promptCString: [CChar]?

    private init() {
        // Private initializer without context
    }

    init(context: OpaquePointer) {
        self.context = context
    }

    deinit {
        if let context = context {
            whisper_free(context)
        }
    }

    func fullTranscribe(samples: [Float]) {
        guard let context = context else { return }
        
        // Leave 2 processors free (i.e. the high-efficiency cores).
        let maxThreads = max(1, min(8, cpuCount() - 2))
        print("Selecting \(maxThreads) threads")
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        
        // Read language directly from UserDefaults
        let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        if selectedLanguage != "auto" {
            languageCString = Array(selectedLanguage.utf8CString)
            params.language = languageCString?.withUnsafeBufferPointer { ptr in
                ptr.baseAddress
            }
            print("Setting language to: \(selectedLanguage)")
        } else {
            languageCString = nil
            params.language = nil
            print("Using auto-detection")
        }
        
        // Only use prompt for English language
        if selectedLanguage == "en" && prompt != nil {
            promptCString = Array(prompt!.utf8CString)
            params.initial_prompt = promptCString?.withUnsafeBufferPointer { ptr in
                ptr.baseAddress
            }
            print("Using prompt for English transcription: \(prompt!)")
        } else {
            promptCString = nil
            params.initial_prompt = nil
            if selectedLanguage == "en" {
                print("No prompt set for English")
            } else {
                print("Prompt disabled for non-English language")
            }
        }
        
        // Adapted from whisper.objc
        params.print_realtime   = true
        params.print_progress   = false
        params.print_timestamps = true
        params.print_special    = false
        params.translate        = false
        params.n_threads        = Int32(maxThreads)
        params.offset_ms        = 0
        params.no_context       = true
        params.single_segment   = false

        whisper_reset_timings(context)
        print("About to run whisper_full")
        samples.withUnsafeBufferPointer { samples in
            if (whisper_full(context, params, samples.baseAddress, Int32(samples.count)) != 0) {
                print("Failed to run the model")
            } else {
                // Print detected language info before timings
                let langId = whisper_full_lang_id(context)
                let detectedLang = String(cString: whisper_lang_str(langId))
                print("Transcription completed - Selected: \(selectedLanguage), Used: \(detectedLang)")
                whisper_print_timings(context)
            }
        }
        
        languageCString = nil
        promptCString = nil
    }

    func getTranscription() -> String {
        guard let context = context else { return "" }
        var transcription = ""
        for i in 0..<whisper_full_n_segments(context) {
            transcription += String(cString: whisper_full_get_segment_text(context, i))
        }
        return transcription
    }

    static func createContext(path: String) async throws -> WhisperContext {
        // Create empty context first
        let whisperContext = WhisperContext()
        
        // Initialize the context within the actor's isolated context
        try await whisperContext.initializeModel(path: path)
        
        return whisperContext
    }
    
    private func initializeModel(path: String) throws {
        var params = whisper_context_default_params()
        #if targetEnvironment(simulator)
        params.use_gpu = false
        print("Running on the simulator, using CPU")
        #endif
        
        let context = whisper_init_from_file_with_params(path, params)
        if let context {
            self.context = context
        } else {
            print("Couldn't load model at \(path)")
            throw WhisperError.couldNotInitializeContext
        }
    }

    func releaseResources() {
        if let context = context {
            whisper_free(context)
            self.context = nil
        }
        languageCString = nil
    }

    func setPrompt(_ prompt: String?) {
        self.prompt = prompt
        print("Prompt set to: \(prompt ?? "none")")
    }
}

fileprivate func cpuCount() -> Int {
    ProcessInfo.processInfo.processorCount
}
