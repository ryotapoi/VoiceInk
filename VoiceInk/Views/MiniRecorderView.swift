import SwiftUI

struct MiniRecorderView: View {
    @ObservedObject var whisperState: WhisperState
    @ObservedObject var recorder: Recorder
    @EnvironmentObject var windowManager: MiniWindowManager
    @State private var showPromptPopover = false
    
    var body: some View {
        Group {
            if windowManager.isVisible {
                Capsule()
                    .fill(.clear)
                    .background(
                        ZStack {
                            // Base dark background
                            Color.black.opacity(0.9)
                            
                            // Subtle gradient overlay
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.95),
                                    Color(red: 0.15, green: 0.15, blue: 0.15).opacity(0.9)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            
                            // Very subtle visual effect for depth
                            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                                .opacity(0.05)
                        }
                        .clipShape(Capsule())
                    )
                    .overlay {
                        // Subtle inner border
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                    }
                    .overlay {
                        HStack(spacing: 16) {
                            // Record Button
                            NotchRecordButton(
                                isRecording: whisperState.isRecording,
                                isProcessing: whisperState.isProcessing
                            ) {
                                Task { await whisperState.toggleRecord() }
                            }
                            .frame(width: 18)
                            .padding(.leading, -4)
                            
                            // AI Enhancement Toggle
                            if let enhancementService = whisperState.getEnhancementService() {
                                NotchToggleButton(
                                    isEnabled: enhancementService.isEnhancementEnabled,
                                    icon: "sparkles",
                                    color: .blue
                                ) {
                                    enhancementService.isEnhancementEnabled.toggle()
                                }
                                .frame(width: 18)
                                .disabled(!enhancementService.isConfigured)
                            }
                            
                            // Custom Prompt Toggle and Selector
                            if let enhancementService = whisperState.getEnhancementService() {
                                NotchToggleButton(
                                    isEnabled: enhancementService.isEnhancementEnabled,
                                    icon: enhancementService.activePrompt?.icon.rawValue ?? "text.badge.checkmark",
                                    color: .green
                                ) {
                                    showPromptPopover.toggle()
                                }
                                .frame(width: 18)
                                .disabled(!enhancementService.isEnhancementEnabled)
                                .popover(isPresented: $showPromptPopover, arrowEdge: .bottom) {
                                    NotchPromptPopover(enhancementService: enhancementService)
                                }
                            }
                            
                            // Visualizer
                            Group {
                                if whisperState.isProcessing {
                                    NotchStaticVisualizer(color: .white)
                                } else {
                                    NotchAudioVisualizer(
                                        audioMeter: recorder.audioMeter,
                                        color: .white,
                                        isActive: whisperState.isRecording
                                    )
                                }
                            }
                            .frame(width: 18)
                            .padding(.trailing, -4)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                    }
                    .opacity(windowManager.isVisible ? 1 : 0)
            }
        }
    }
}

// Visual Effect View wrapper for NSVisualEffectVie
