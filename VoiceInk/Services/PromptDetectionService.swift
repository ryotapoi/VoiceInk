import Foundation
import os

class PromptDetectionService {
    private let logger = Logger(
        subsystem: "com.prakashjoshipax.VoiceInk",
        category: "promptdetection"
    )
    
    struct PromptDetectionResult {
        let shouldEnableAI: Bool
        let selectedPromptId: UUID?
        let processedText: String
        let detectedTriggerWord: String?
        let originalEnhancementState: Bool
        let originalPromptId: UUID?
    }
    
    func analyzeText(_ text: String, with enhancementService: AIEnhancementService) -> PromptDetectionResult {
        let originalEnhancementState = enhancementService.isEnhancementEnabled
        let originalPromptId = enhancementService.selectedPromptId
        
        if let result = checkAssistantTrigger(text: text, triggerWord: enhancementService.assistantTriggerWord) {
            return PromptDetectionResult(
                shouldEnableAI: true,
                selectedPromptId: PredefinedPrompts.assistantPromptId,
                processedText: result,
                detectedTriggerWord: enhancementService.assistantTriggerWord,
                originalEnhancementState: originalEnhancementState,
                originalPromptId: originalPromptId
            )
        }
        
        for prompt in enhancementService.allPrompts {
            if let triggerWord = prompt.triggerWord?.trimmingCharacters(in: .whitespacesAndNewlines),
               !triggerWord.isEmpty,
               let result = checkCustomTrigger(text: text, triggerWord: triggerWord) {
                
                return PromptDetectionResult(
                    shouldEnableAI: true,
                    selectedPromptId: prompt.id,
                    processedText: result,
                    detectedTriggerWord: triggerWord,
                    originalEnhancementState: originalEnhancementState,
                    originalPromptId: originalPromptId
                )
            }
        }
        
        return PromptDetectionResult(
            shouldEnableAI: false,
            selectedPromptId: nil,
            processedText: text,
            detectedTriggerWord: nil,
            originalEnhancementState: originalEnhancementState,
            originalPromptId: originalPromptId
        )
    }
    
    func applyDetectionResult(_ result: PromptDetectionResult, to enhancementService: AIEnhancementService) async {
        await MainActor.run {
            if result.shouldEnableAI {
                if !enhancementService.isEnhancementEnabled {
                    enhancementService.isEnhancementEnabled = true
                }
                if let promptId = result.selectedPromptId {
                    enhancementService.selectedPromptId = promptId
                }
            }
        }
        
        if result.shouldEnableAI {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
    
    func restoreOriginalSettings(_ result: PromptDetectionResult, to enhancementService: AIEnhancementService) async {
        if result.shouldEnableAI {
            await MainActor.run {
                if enhancementService.isEnhancementEnabled != result.originalEnhancementState {
                    enhancementService.isEnhancementEnabled = result.originalEnhancementState
                }
                if let originalId = result.originalPromptId, enhancementService.selectedPromptId != originalId {
                    enhancementService.selectedPromptId = originalId
                }
            }
        }
    }
    
    private func checkAssistantTrigger(text: String, triggerWord: String) -> String? {
        return removeTriggerWord(from: text, triggerWord: triggerWord)
    }
    
    private func checkCustomTrigger(text: String, triggerWord: String) -> String? {
        return removeTriggerWord(from: text, triggerWord: triggerWord)
    }
    
    private func removeTriggerWord(from text: String, triggerWord: String) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerText = trimmedText.lowercased()
        let lowerTrigger = triggerWord.lowercased()
        
        guard lowerText.hasPrefix(lowerTrigger) else { return nil }
        
        let triggerEndIndex = trimmedText.index(trimmedText.startIndex, offsetBy: triggerWord.count)
        
        if triggerEndIndex >= trimmedText.endIndex {
            return ""
        }
        
        var remainingText = String(trimmedText[triggerEndIndex...])
        
        remainingText = remainingText.replacingOccurrences(
            of: "^[,\\.!\\?;:\\s]+",
            with: "",
            options: .regularExpression
        )
        
        remainingText = remainingText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !remainingText.isEmpty {
            remainingText = remainingText.prefix(1).uppercased() + remainingText.dropFirst()
        }
        
        return remainingText
    }
}