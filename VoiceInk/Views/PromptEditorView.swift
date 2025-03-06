import SwiftUI

struct PromptEditorView: View {
    enum Mode {
        case add
        case edit(CustomPrompt)
        
        static func == (lhs: Mode, rhs: Mode) -> Bool {
            switch (lhs, rhs) {
            case (.add, .add):
                return true
            case let (.edit(prompt1), .edit(prompt2)):
                return prompt1.id == prompt2.id
            default:
                return false
            }
        }
    }
    
    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @State private var title: String
    @State private var promptText: String
    @State private var selectedIcon: PromptIcon
    @State private var description: String
    @State private var showingPredefinedPrompts = false
    
    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .add:
            _title = State(initialValue: "")
            _promptText = State(initialValue: "")
            _selectedIcon = State(initialValue: .documentFill)
            _description = State(initialValue: "")
        case .edit(let prompt):
            _title = State(initialValue: prompt.title)
            _promptText = State(initialValue: prompt.promptText)
            _selectedIcon = State(initialValue: prompt.icon)
            _description = State(initialValue: prompt.description ?? "")
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with modern styling
            HStack {
                Text(mode == .add ? "New Mode" : "Edit Mode")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                HStack(spacing: 12) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    
                    Button {
                        save()
                        dismiss()
                    } label: {
                        Text("Save")
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.isEmpty || promptText.isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding()
            .background(
                Color(NSColor.windowBackgroundColor)
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
            )
            
            ScrollView {
                VStack(spacing: 24) {
                    // Title and Icon Section with improved layout
                    HStack(spacing: 20) {
                        // Title Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Title")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            TextField("Enter a short, descriptive title", text: $title)
                                .textFieldStyle(.roundedBorder)
                                .font(.body)
                        }
                        .frame(maxWidth: .infinity)
                        
                        // Icon Selector with preview
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Icon")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Menu {
                                IconMenuContent(selectedIcon: $selectedIcon)
                            } label: {
                                HStack {
                                    Image(systemName: selectedIcon.rawValue)
                                        .font(.system(size: 16))
                                        .foregroundColor(.accentColor)
                                        .frame(width: 24)
                                    
                                    Text(selectedIcon.title)
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                            }
                            .frame(width: 180)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // Description Field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Add a brief description of what this mode does")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        TextField("Enter a description", text: $description)
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                    }
                    .padding(.horizontal)
                    
                    // Prompt Text Section with improved styling
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mode Instructions")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Define how AI should enhance your transcriptions")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        TextEditor(text: $promptText)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 200)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(NSColor.textBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal)
                    
                    if case .add = mode {
                        // Templates Section with improved styling
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Start with a Predefined Template")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text("Scroll horizontally to see more templates")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(PromptTemplates.all) { template in
                                        TemplateButton(prompt: template) {
                                            title = template.title
                                            promptText = template.promptText
                                            selectedIcon = template.icon
                                            description = template.description
                                        }
                                    }
                                }
                                .padding(.horizontal, 2)
                                .padding(.bottom, 2)
                            }
                            .scrollClipDisabled(true)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 20)
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }
    
    private func save() {
        switch mode {
        case .add:
            enhancementService.addPrompt(
                title: title,
                promptText: promptText,
                icon: selectedIcon,
                description: description.isEmpty ? nil : description
            )
        case .edit(let prompt):
            let updatedPrompt = CustomPrompt(
                id: prompt.id,
                title: title,
                promptText: promptText,
                isActive: prompt.isActive,
                icon: selectedIcon,
                description: description.isEmpty ? nil : description
            )
            enhancementService.updatePrompt(updatedPrompt)
        }
    }
}

// Template button with modern styling
struct TemplateButton: View {
    let prompt: TemplatePrompt
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: prompt.icon.rawValue)
                        .font(.system(size: 16))
                        .foregroundColor(.accentColor)
                    Text(prompt.title)
                        .fontWeight(.medium)
                }
                
                Text(prompt.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(width: 200, alignment: .leading)
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// Icon menu content for better organization
struct IconMenuContent: View {
    @Binding var selectedIcon: PromptIcon
    
    var body: some View {
        Group {
            IconMenuSection(title: "Document & Text", icons: [.documentFill, .textbox, .sealedFill], selectedIcon: $selectedIcon)
            IconMenuSection(title: "Communication", icons: [.chatFill, .messageFill, .emailFill], selectedIcon: $selectedIcon)
            IconMenuSection(title: "Professional", icons: [.meetingFill, .presentationFill, .briefcaseFill], selectedIcon: $selectedIcon)
            IconMenuSection(title: "Technical", icons: [.codeFill, .terminalFill, .gearFill], selectedIcon: $selectedIcon)
            IconMenuSection(title: "Content", icons: [.blogFill, .notesFill, .bookFill, .bookmarkFill, .pencilFill], selectedIcon: $selectedIcon)
            IconMenuSection(title: "Media & Creative", icons: [.videoFill, .micFill, .musicFill, .photoFill, .brushFill], selectedIcon: $selectedIcon)
        }
    }
}

// Icon menu section for better organization
struct IconMenuSection: View {
    let title: String
    let icons: [PromptIcon]
    @Binding var selectedIcon: PromptIcon
    
    var body: some View {
        Group {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            ForEach(icons, id: \.self) { icon in
                Button(action: { selectedIcon = icon }) {
                    Label(icon.title, systemImage: icon.rawValue)
                }
            }
            if title != "Media & Creative" {
                Divider()
            }
        }
    }
} 