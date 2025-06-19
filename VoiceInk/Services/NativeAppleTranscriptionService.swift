import Foundation
import AVFoundation
import os

#if canImport(Speech)
import Speech
#endif

/// Transcription service that leverages the new SpeechAnalyzer / SpeechTranscriber API available on macOS 26 (Tahoe).
/// Falls back with an unsupported-provider error on earlier OS versions so the application can gracefully degrade.
class NativeAppleTranscriptionService: TranscriptionService {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "NativeAppleTranscriptionService")
    
    enum ServiceError: Error, LocalizedError {
        case unsupportedOS
        case transcriptionFailed
        case localeNotSupported
        case invalidModel
        
        var errorDescription: String? {
            switch self {
            case .unsupportedOS:
                return "SpeechAnalyzer requires macOS 26 or later."
            case .transcriptionFailed:
                return "Transcription failed using SpeechAnalyzer."
            case .localeNotSupported:
                return "The selected language is not supported by SpeechAnalyzer."
            case .invalidModel:
                return "Invalid model type provided for Native Apple transcription."
            }
        }
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        guard model is NativeAppleModel else {
            throw ServiceError.invalidModel
        }
        
        guard #available(macOS 26, *) else {
            logger.error("SpeechAnalyzer is not available on this macOS version")
            throw ServiceError.unsupportedOS
        }
        
        #if canImport(Speech)
        logger.notice("Starting Apple native transcription with SpeechAnalyzer.")
        
        let audioFile = try AVAudioFile(forReading: audioURL)
        
        // Use the user's selected language directly, assuming BCP-47 format.
        let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "en-US"
        let locale = Locale(identifier: selectedLanguage)

        // Check for locale support and asset installation status.
        let supportedLocales = await SpeechTranscriber.supportedLocales
        let installedLocales = await SpeechTranscriber.installedLocales
        let isLocaleSupported = supportedLocales.contains(locale)
        let isLocaleInstalled = installedLocales.contains(locale)

        // Create the detailed log message
        let supportedIdentifiers = supportedLocales.map { $0.identifier }.sorted().joined(separator: ", ")
        let installedIdentifiers = installedLocales.map { $0.identifier }.sorted().joined(separator: ", ")
        let availableForDownload = Set(supportedLocales).subtracting(Set(installedLocales)).map { $0.identifier }.sorted().joined(separator: ", ")
        
        var statusMessage: String
        if isLocaleInstalled {
            statusMessage = "✅ Installed"
        } else if isLocaleSupported {
            statusMessage = "❌ Not Installed (Available for download)"
        } else {
            statusMessage = "❌ Not Supported"
        }
        
        let logMessage = """
        
        --- Native Speech Transcription ---
        Locale: '\(locale.identifier)'
        Status: \(statusMessage)
        ------------------------------------
        Supported Locales: [\(supportedIdentifiers)]
        Installed Locales: [\(installedIdentifiers)]
        Available for Download: [\(availableForDownload)]
        ------------------------------------
        """
        logger.notice("\(logMessage)")

        guard isLocaleSupported else {
            logger.error("Transcription failed: Locale '\(locale.identifier)' is not supported by SpeechTranscriber.")
            throw ServiceError.localeNotSupported
        }
        
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        
        // Ensure model assets are available, triggering a system download prompt if necessary.
        try await ensureModelIsAvailable(for: transcriber, locale: locale)
        
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        
        try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
        
        var transcript: AttributedString = ""
        for try await result in transcriber.results {
            transcript += result.text
        }
        
        let finalTranscription = String(transcript.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        
        logger.notice("Native transcription successful. Length: \(finalTranscription.count) characters.")
        return finalTranscription
        
        #else
        logger.error("Speech framework is not available")
        throw ServiceError.unsupportedOS
        #endif
    }
    
    @available(macOS 26, *)
    private func ensureModelIsAvailable(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        #if canImport(Speech)
        let isInstalled = await SpeechTranscriber.installedLocales.contains(locale)

        if !isInstalled {
            logger.notice("Assets for '\(locale.identifier)' not installed. Requesting system download.")
            
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
                logger.notice("Asset download for '\(locale.identifier)' complete.")
            } else {
                logger.error("Asset download for '\(locale.identifier)' failed: Could not create installation request.")
                // Note: We don't throw an error here, as transcription might still work with a base model.
            }
        }
        #endif
    }
} 
