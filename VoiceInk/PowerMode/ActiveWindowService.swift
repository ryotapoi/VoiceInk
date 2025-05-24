import Foundation
import AppKit
import os

class ActiveWindowService: ObservableObject {
    static let shared = ActiveWindowService()
    @Published var currentApplication: NSRunningApplication?
    private var enhancementService: AIEnhancementService?
    private let browserURLService = BrowserURLService.shared
    private var whisperState: WhisperState?
    
    private let logger = Logger(
        subsystem: "com.prakashjoshipax.VoiceInk",
        category: "browser.detection"
    )
    
    private init() {}
    
    func configure(with enhancementService: AIEnhancementService) {
        self.enhancementService = enhancementService
    }
    
    func configureWhisperState(_ whisperState: WhisperState) {
        self.whisperState = whisperState
    }
    
    func applyConfigurationForCurrentApp() async {
        // If power mode is disabled, don't do anything
        guard PowerModeManager.shared.isPowerModeEnabled else {
            print("🔌 Power Mode is disabled globally - skipping configuration application")
            return
        }

        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = frontmostApp.bundleIdentifier else { return }
        
        print("🎯 Active Application: \(frontmostApp.localizedName ?? "Unknown") (\(bundleIdentifier))")
        await MainActor.run {
            currentApplication = frontmostApp
        }
        
        // Check if the current app is a supported browser
        if let browserType = BrowserType.allCases.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            logger.debug("🌐 Detected Browser: \(browserType.displayName)")
            
            do {
                // Try to get the current URL
                logger.debug("📝 Attempting to get URL from \(browserType.displayName)")
                let currentURL = try await browserURLService.getCurrentURL(from: browserType)
                logger.debug("📍 Successfully got URL: \(currentURL)")
                
                // Check for URL-specific configuration
                if let config = PowerModeManager.shared.getConfigurationForURL(currentURL) {
                    logger.debug("⚙️ Found URL Configuration: \(config.name) for URL: \(currentURL)")
                    // Set as active configuration in PowerModeManager
                    await MainActor.run {
                        PowerModeManager.shared.setActiveConfiguration(config)
                    }
                    // Apply URL-specific configuration
                    await applyConfiguration(config)
                    return
                } else {
                    logger.debug("📝 No URL configuration found for: \(currentURL)")
                }
            } catch {
                logger.error("❌ Failed to get URL from \(browserType.displayName): \(error.localizedDescription)")
            }
        }
        
        // Get configuration for the current app or use default if none exists
        let config = PowerModeManager.shared.getConfigurationForApp(bundleIdentifier) ?? PowerModeManager.shared.defaultConfig
        print("⚡️ Using Configuration: \(config.name) (AI Enhancement: \(config.isAIEnhancementEnabled ? "Enabled" : "Disabled"))")
        
        // Set as active configuration in PowerModeManager
        await MainActor.run {
            PowerModeManager.shared.setActiveConfiguration(config)
        }
        
        await applyConfiguration(config)
    }
    
    /// Applies a specific configuration
    func applyConfiguration(_ config: PowerModeConfig) async {
        guard let enhancementService = enhancementService else { return }
        

        await MainActor.run {
            // Apply AI enhancement settings
            enhancementService.isEnhancementEnabled = config.isAIEnhancementEnabled
            enhancementService.useScreenCaptureContext = config.useScreenCapture
            
            // Handle prompt selection
            if config.isAIEnhancementEnabled {
                if let promptId = config.selectedPrompt,
                   let uuid = UUID(uuidString: promptId) {
                    print("🎯 Applied Prompt: \(promptId)")
                    enhancementService.selectedPromptId = uuid
                } else {
                    // Auto-select first prompt if none is selected and AI is enabled
                    if let firstPrompt = enhancementService.allPrompts.first {
                        print("🎯 Auto-selected Prompt: \(firstPrompt.title)")
                        enhancementService.selectedPromptId = firstPrompt.id
                    }
                }
            }
            
            // Apply AI provider and model if specified
            if config.isAIEnhancementEnabled, 
               let aiService = enhancementService.getAIService() {
                
                // Apply AI provider if specified, otherwise use current global provider
                if let providerName = config.selectedAIProvider,
                   let provider = AIProvider(rawValue: providerName) {
                    print("🤖 Applied AI Provider: \(provider.rawValue)")
                    aiService.selectedProvider = provider
                    
                    // Apply model if specified, otherwise use default model
                    if let model = config.selectedAIModel,
                       !model.isEmpty {
                        print("🧠 Applied AI Model: \(model)")
                        aiService.selectModel(model)
                    } else {
                        print("🧠 Using default model for provider: \(aiService.currentModel)")
                    }
                } else {
                    print("🤖 Using global AI Provider: \(aiService.selectedProvider.rawValue)")
                }
            }
            
            // Apply language selection if specified
            if let language = config.selectedLanguage {
                print("🌐 Applied Language: \(language)")
                UserDefaults.standard.set(language, forKey: "SelectedLanguage")
                // Notify that language has changed to update the prompt
                NotificationCenter.default.post(name: .languageDidChange, object: nil)
            }
        }
        
        // Apply Whisper model selection - do this outside of MainActor to allow async operations
        if let whisperState = self.whisperState,
           let modelName = config.selectedWhisperModel,
           let selectedModel = await whisperState.availableModels.first(where: { $0.name == modelName }) {
            print("🎤 Applied Whisper Model: \(selectedModel.name)")
            await whisperState.setDefaultModel(selectedModel)
            
            await whisperState.cleanupModelResources()
            
            do {
                try await whisperState.loadModel(selectedModel)
                print("🎤 Loaded Whisper Model: \(selectedModel.name)")
            } catch {
                print("❌ Failed to load Whisper Model: \(error.localizedDescription)")
            }
        }
    }
} 
