import Foundation
import AppKit
import Vision
import os

class ScreenCaptureService: ObservableObject {
    @Published var isCapturing = false
    @Published var lastCapturedText: String?
    
    private let logger = Logger(
        subsystem: "com.prakashjoshipax.VoiceInk",
        category: "aienhancement"
    )
    
    private func getActiveWindowInfo() -> (title: String, ownerName: String, windowID: CGWindowID)? {
        let options = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
        let windowListInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        
        // Find the frontmost window that isn't our own app
        guard let frontWindow = windowListInfo.first(where: { info in
            let layer = info[kCGWindowLayer as String] as? Int32 ?? 0
            let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
            // Exclude our own app and system UI elements
            return layer == 0 && ownerName != "VoiceInk" && !ownerName.contains("Dock") && !ownerName.contains("Menu Bar")
        }) else {
            return nil
        }
        
        guard let windowID = frontWindow[kCGWindowNumber as String] as? CGWindowID,
              let ownerName = frontWindow[kCGWindowOwnerName as String] as? String,
              let title = frontWindow[kCGWindowName as String] as? String else {
            return nil
        }
        
        return (title: title, ownerName: ownerName, windowID: windowID)
    }
    
    func captureActiveWindow() -> NSImage? {
        guard let windowInfo = getActiveWindowInfo() else {
            return nil
        }
        
        // Capture the window
        let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowInfo.windowID,
            [.boundsIgnoreFraming, .bestResolution]
        )
        
        guard let cgImage = cgImage else {
            return nil
        }
        
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
    
    func extractText(from image: NSImage, completion: @escaping (String?) -> Void) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(nil)
            return
        }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest { request, error in
            guard error == nil,
                  let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(nil)
                return
            }
            
            let text = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }.joined(separator: "\n")
            
            completion(text)
        }
        
        // Configure the recognition level
        request.recognitionLevel = .accurate
        
        do {
            try requestHandler.perform([request])
        } catch {
            completion(nil)
        }
    }
    
    func captureAndExtractText() async -> String? {
        guard !isCapturing else { return nil }
        
        isCapturing = true
        defer { isCapturing = false }
        
        logger.notice("🎬 Starting screen capture")
        
        // First get window info
        guard let windowInfo = getActiveWindowInfo() else {
            logger.notice("❌ Failed to get window info")
            return nil
        }
        
        logger.notice("🎯 Found window: \(windowInfo.title) (\(windowInfo.ownerName))")
        
        // Start with window metadata
        var contextText = """
        Active Window: \(windowInfo.title)
        Application: \(windowInfo.ownerName)
        
        """
        
        // Then capture and process window content
        if let capturedImage = captureActiveWindow() {
            if let extractedText = await withCheckedContinuation({ continuation in
                extractText(from: capturedImage) { text in
                    continuation.resume(returning: text)
                }
            }) {
                contextText += "Window Content:\n\(extractedText)"
                // Log immediately after text extraction
                logger.notice("✅ Captured: \(contextText)")
            }
        }
        
        self.lastCapturedText = contextText
        return contextText
    }
} 