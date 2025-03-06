import SwiftUI
// Supporting Views
struct PowerModeEmptyStateView: View {
    @Binding var showAddModal: Bool
    @Binding var configMode: ConfigurationMode?
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Applications Configured")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add applications to customize their AI enhancement settings.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: { 
                print("🔍 Empty state Add Application button clicked")
                configMode = .add
                print("🔍 Configuration mode set to: \(String(describing: configMode))")
                showAddModal = true 
                print("🔍 Empty state showAddModal set to: \(showAddModal)")
            }) {
                Label("Add Application", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        
    }
}

struct ConfiguredAppsGrid: View {
    @ObservedObject var powerModeManager: PowerModeManager
    @EnvironmentObject var enhancementService: AIEnhancementService
    @State private var editingConfig: PowerModeConfig?
    @State private var showingConfigSheet = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(powerModeManager.configurations.sorted(by: { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending })) { config in
                    ConfiguredAppRow(
                        config: config,
                        isEditing: editingConfig?.id == config.id,
                        action: { 
                            editingConfig = config
                            showingConfigSheet = true
                        }
                    )
                    .contextMenu {
                        Button(action: { 
                            editingConfig = config
                            showingConfigSheet = true
                        }) {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive, action: {
                            powerModeManager.removeConfiguration(for: config.bundleIdentifier)
                        }) {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingConfigSheet, onDismiss: { editingConfig = nil }) {
            if let config = editingConfig {
                ConfigurationSheet(
                    mode: .edit(config),
                    isPresented: $showingConfigSheet,
                    powerModeManager: powerModeManager
                )
                .environmentObject(enhancementService)
            }
        }
    }
}

struct ConfiguredAppRow: View {
    let config: PowerModeConfig
    let isEditing: Bool
    let action: () -> Void
    @EnvironmentObject var enhancementService: AIEnhancementService
    
    private var selectedPrompt: CustomPrompt? {
        guard let promptId = config.selectedPrompt,
              let uuid = UUID(uuidString: promptId) else { return nil }
        return enhancementService.allPrompts.first { $0.id == uuid }
    }
    
    private var isWebsiteConfig: Bool {
        return config.urlConfigs != nil && !config.urlConfigs!.isEmpty
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Icon
                if isWebsiteConfig {
                    Image(systemName: "globe")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .foregroundColor(.accentColor)
                } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: config.bundleIdentifier) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                        .resizable()
                        .frame(width: 32, height: 32)
                }
                
                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(config.appName)
                        .font(.headline)
                    if isWebsiteConfig {
                        if let urlConfig = config.urlConfigs?.first {
                            Text(urlConfig.url)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text(config.bundleIdentifier)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: config.isAIEnhancementEnabled ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(config.isAIEnhancementEnabled ? .accentColor : .secondary)
                            .font(.system(size: 14))
                        Text("AI Enhancement")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(config.isAIEnhancementEnabled ? .accentColor : .secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(config.isAIEnhancementEnabled ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.1)))
                    
                    if config.isAIEnhancementEnabled {
                        if let prompt = selectedPrompt {
                            HStack(spacing: 4) {
                                Image(systemName: prompt.icon.rawValue)
                                    .foregroundColor(.accentColor)
                                    .font(.system(size: 14))
                                Text(prompt.title)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentColor.opacity(0.1)))
                        } else {
                            Text("No Prompt")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.secondary.opacity(0.1)))
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(isEditing ? Color.accentColor.opacity(0.1) : Color(.windowBackgroundColor).opacity(0.4)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(isEditing ? Color.accentColor : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct AppConfigurationFormView: View {
    let appName: String?
    let appIcon: NSImage?
    let isDefaultConfig: Bool
    @Binding var isAIEnhancementEnabled: Bool
    @Binding var selectedPromptId: UUID?
    @EnvironmentObject var enhancementService: AIEnhancementService
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 16) {
                if !isDefaultConfig {
                    if let appIcon = appIcon {
                        HStack {
                            Image(nsImage: appIcon)
                                .resizable()
                                .frame(width: 32, height: 32)
                            Text(appName ?? "")
                                .font(.headline)
                            Spacer()
                        }
                    }
                } else {
                    HStack {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.accentColor)
                        Text("Default Settings")
                            .font(.headline)
                        Spacer()
                    }
                    
                    Text("These settings will be applied to all applications that don't have specific configurations.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                }
                
                Toggle("AI Enhancement", isOn: $isAIEnhancementEnabled)
            }
            .padding(.horizontal)
            
            if isAIEnhancementEnabled {
                Divider()
                
                VStack(alignment: .leading) {
                    Text("Select Prompt")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    let columns = [
                        GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 36)
                    ]
                    
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(enhancementService.allPrompts) { prompt in
                            prompt.promptIcon(
                                isSelected: selectedPromptId == prompt.id,
                                onTap: { selectedPromptId = prompt.id }
                            )
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.vertical)
    }
}

struct AppGridItem: View {
    let app: (url: URL, name: String, bundleId: String, icon: NSImage)
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 48, height: 48)
                Text(app.name)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 32)
            }
            .frame(width: 100)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// New component for feature highlights
struct FeatureHighlight: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            
            Text(description)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
} 
