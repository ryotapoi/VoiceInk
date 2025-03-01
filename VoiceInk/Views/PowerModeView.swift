import SwiftUI

// Configuration Mode Enum
enum ConfigurationMode {
    case add
    case edit(PowerModeConfig)
    case editDefault(PowerModeConfig)
    
    var isAdding: Bool {
        if case .add = self { return true }
        return false
    }
    
    var isEditingDefault: Bool {
        if case .editDefault = self { return true }
        return false
    }
    
    var title: String {
        switch self {
        case .add: return "Add Configuration"
        case .editDefault: return "Edit Default Configuration"
        case .edit: return "Edit Configuration"
        }
    }
}

// Configuration Type
enum ConfigurationType {
    case application
    case website
}

// Main Configuration Sheet
struct ConfigurationSheet: View {
    let mode: ConfigurationMode
    @Binding var isPresented: Bool
    let powerModeManager: PowerModeManager
    @EnvironmentObject var enhancementService: AIEnhancementService
    
    // State for configuration
    @State private var configurationType: ConfigurationType = .application
    @State private var selectedAppURL: URL?
    @State private var isAIEnhancementEnabled: Bool
    @State private var selectedPromptId: UUID?
    @State private var installedApps: [(url: URL, name: String, bundleId: String, icon: NSImage)] = []
    @State private var searchText = ""
    
    // Website configuration state
    @State private var websiteURL: String = ""
    @State private var websiteName: String = ""
    
    private var filteredApps: [(url: URL, name: String, bundleId: String, icon: NSImage)] {
        if searchText.isEmpty {
            return installedApps
        }
        return installedApps.filter { app in
            app.name.localizedCaseInsensitiveContains(searchText) ||
            app.bundleId.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    init(mode: ConfigurationMode, isPresented: Binding<Bool>, powerModeManager: PowerModeManager) {
        self.mode = mode
        self._isPresented = isPresented
        self.powerModeManager = powerModeManager
        
        switch mode {
        case .add:
            _isAIEnhancementEnabled = State(initialValue: true)
            _selectedPromptId = State(initialValue: nil)
        case .edit(let config), .editDefault(let config):
            _isAIEnhancementEnabled = State(initialValue: config.isAIEnhancementEnabled)
            _selectedPromptId = State(initialValue: config.selectedPrompt.flatMap { UUID(uuidString: $0) })
            if case .edit(let config) = mode {
                // Initialize website configuration if it exists
                if let urlConfig = config.urlConfigs?.first {
                    _configurationType = State(initialValue: .website)
                    _websiteURL = State(initialValue: urlConfig.url)
                    _websiteName = State(initialValue: config.appName)
                } else {
                    _configurationType = State(initialValue: .application)
                    _selectedAppURL = State(initialValue: NSWorkspace.shared.urlForApplication(withBundleIdentifier: config.bundleIdentifier))
                }
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(mode.title)
                    .font(.headline)
                Spacer()
            }
            .padding()
            
            Divider()
            
            if mode.isAdding {
                // Configuration Type Selector
                Picker("Configuration Type", selection: $configurationType) {
                    Text("Application").tag(ConfigurationType.application)
                    Text("Website").tag(ConfigurationType.website)
                }
                
                .padding()
                
                if configurationType == .application {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search applications...", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(8)
                    .background(Color(.windowBackgroundColor).opacity(0.4))
                    .cornerRadius(8)
                    .padding()
                    
                    // App Grid
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 16)], spacing: 16) {
                            ForEach(filteredApps.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }), id: \.bundleId) { app in
                                AppGridItem(
                                    app: app,
                                    isSelected: app.url == selectedAppURL,
                                    action: { selectedAppURL = app.url }
                                )
                            }
                        }
                        .padding()
                    }
                } else {
                    // Website Configuration
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Website Name")
                                .font(.headline)
                            TextField("Enter website name", text: $websiteName)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Website URL")
                                .font(.headline)
                            TextField("Enter website URL (e.g., google.com)", text: $websiteURL)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding()
                }
            }
            
            // Configuration Form
            if let config = getConfigForForm() {
                if let appURL = !mode.isEditingDefault ? NSWorkspace.shared.urlForApplication(withBundleIdentifier: config.bundleIdentifier) : nil {
                    AppConfigurationFormView(
                        appName: config.appName,
                        appIcon: NSWorkspace.shared.icon(forFile: appURL.path),
                        isDefaultConfig: mode.isEditingDefault,
                        isAIEnhancementEnabled: $isAIEnhancementEnabled,
                        selectedPromptId: $selectedPromptId
                    )
                } else {
                    AppConfigurationFormView(
                        appName: nil,
                        appIcon: nil,
                        isDefaultConfig: mode.isEditingDefault,
                        isAIEnhancementEnabled: $isAIEnhancementEnabled,
                        selectedPromptId: $selectedPromptId
                    )
                }
            }
            
            Divider()
            
            // Bottom buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                Button(mode.isAdding ? "Add" : "Save") {
                    saveConfiguration()
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(mode.isAdding && !canSave)
            }
            .padding()
        }
        .frame(width: 600)
        .frame(maxHeight: mode.isAdding ? 700 : 600)
        .onAppear {
            print("🔍 ConfigurationSheet appeared - Mode: \(mode)")
            if mode.isAdding {
                print("🔍 Loading installed apps...")
                loadInstalledApps()
            }
        }
    }
    
    private var canSave: Bool {
        if configurationType == .application {
            return selectedAppURL != nil
        } else {
            return !websiteURL.isEmpty && !websiteName.isEmpty
        }
    }
    
    private func getConfigForForm() -> PowerModeConfig? {
        switch mode {
        case .add:
            if configurationType == .application {
                guard let url = selectedAppURL,
                      let bundle = Bundle(url: url),
                      let bundleId = bundle.bundleIdentifier else { return nil }
                
                let appName = bundle.infoDictionary?["CFBundleName"] as? String ??
                             bundle.infoDictionary?["CFBundleDisplayName"] as? String ??
                             "Unknown App"
                
                return PowerModeConfig(
                    bundleIdentifier: bundleId,
                    appName: appName,
                    isAIEnhancementEnabled: isAIEnhancementEnabled,
                    selectedPrompt: selectedPromptId?.uuidString
                )
            } else {
                // Create a special PowerModeConfig for websites
                let urlConfig = URLConfig(url: websiteURL, promptId: selectedPromptId?.uuidString)
                return PowerModeConfig(
                    bundleIdentifier: "website.\(UUID().uuidString)",
                    appName: websiteName,
                    isAIEnhancementEnabled: isAIEnhancementEnabled,
                    selectedPrompt: selectedPromptId?.uuidString,
                    urlConfigs: [urlConfig]
                )
            }
        case .edit(let config), .editDefault(let config):
            return config
        }
    }
    
    private func loadInstalledApps() {
        // Get both user-installed and system applications
        let userAppURLs = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)
        let systemAppURLs = FileManager.default.urls(for: .applicationDirectory, in: .systemDomainMask)
        let allAppURLs = userAppURLs + systemAppURLs
        
        let apps = allAppURLs.flatMap { url -> [URL] in
            return (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        }
        
        installedApps = apps.compactMap { url in
            guard let bundle = Bundle(url: url),
                  let bundleId = bundle.bundleIdentifier,
                  let name = (bundle.infoDictionary?["CFBundleName"] as? String) ??
                            (bundle.infoDictionary?["CFBundleDisplayName"] as? String) else {
                return nil
            }
            
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            return (url: url, name: name, bundleId: bundleId, icon: icon)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    private func saveConfiguration() {
        if isAIEnhancementEnabled && selectedPromptId == nil {
            selectedPromptId = enhancementService.allPrompts.first?.id
        }
        
        switch mode {
        case .add:
            if let config = getConfigForForm() {
                powerModeManager.addConfiguration(config)
            }
        case .edit(let config), .editDefault(let config):
            var updatedConfig = config
            updatedConfig.isAIEnhancementEnabled = isAIEnhancementEnabled
            updatedConfig.selectedPrompt = selectedPromptId?.uuidString
            
            // Update URL configurations if this is a website config
            if configurationType == .website {
                let urlConfig = URLConfig(url: cleanURL(websiteURL), promptId: selectedPromptId?.uuidString)
                updatedConfig.urlConfigs = [urlConfig]
                updatedConfig.appName = websiteName
            }
            
            powerModeManager.updateConfiguration(updatedConfig)
        }
        
        isPresented = false
    }
    
    private func cleanURL(_ url: String) -> String {
        var cleanedURL = url.lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
        
        // Remove trailing slash if present
        if cleanedURL.last == "/" {
            cleanedURL.removeLast()
        }
        
        return cleanedURL
    }
}

// Main View
struct PowerModeView: View {
    @StateObject private var powerModeManager = PowerModeManager.shared
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @State private var showingConfigSheet = false {
        didSet {
            print("🔍 showingConfigSheet changed to: \(showingConfigSheet)")
        }
    }
    @State private var configurationMode: ConfigurationMode? {
        didSet {
            print("🔍 configurationMode changed to: \(String(describing: configurationMode))")
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Video CTA Section
                VideoCTAView(
                    url: "https://dub.sh/powermode",
                    subtitle: "See Power Mode in action"
                )
                
                // Power Mode Toggle Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Enable Power Mode")
                            .font(.headline)
                        Spacer()
                        Toggle("", isOn: $powerModeManager.isPowerModeEnabled)
                            .toggleStyle(SwitchToggleStyle(tint: .blue))
                            .labelsHidden()
                            .scaleEffect(1.2)
                            .onChange(of: powerModeManager.isPowerModeEnabled) { _ in
                                powerModeManager.savePowerModeEnabled()
                            }
                    }
                }
                .padding(.horizontal)
                
                if powerModeManager.isPowerModeEnabled {
                    // Default Configuration Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Default Configuration")
                            .font(.headline)
                        
                        ConfiguredAppRow(
                            config: powerModeManager.defaultConfig,
                            isEditing: configurationMode?.isEditingDefault ?? false,
                            action: { 
                                configurationMode = .editDefault(powerModeManager.defaultConfig)
                                showingConfigSheet = true
                            }
                        )
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.windowBackgroundColor).opacity(0.4)))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor.opacity(0.2), lineWidth: 1))
                    }
                    .padding(.horizontal)
                    
                    // Apps Section
                    VStack(spacing: 16) {
                        if powerModeManager.configurations.isEmpty {
                            PowerModeEmptyStateView(
                                showAddModal: $showingConfigSheet,
                                configMode: $configurationMode
                            )
                        } else {
                            Text("Power Mode Configurations")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                            
                            ConfiguredAppsGrid(powerModeManager: powerModeManager)
                            
                            Button(action: { 
                                print("🔍 Add button clicked - Setting config mode and showing sheet")
                                configurationMode = .add
                                print("🔍 Configuration mode set to: \(String(describing: configurationMode))")
                                showingConfigSheet = true
                                print("🔍 showingConfigSheet set to: \(showingConfigSheet)")
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Add New Mode")
                                        .font(.system(size: 13, weight: .medium))
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                            .tint(Color(NSColor.controlAccentColor))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .help("Add a new mode")
                            .padding(.top, 12)
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .sheet(isPresented: $showingConfigSheet, onDismiss: { 
            print("🔍 Sheet dismissed - Clearing configuration mode")
            configurationMode = nil 
        }) {
            Group {
                if let mode = configurationMode {
                    ConfigurationSheet(
                        mode: mode,
                        isPresented: $showingConfigSheet,
                        powerModeManager: powerModeManager
                    )
                    .environmentObject(enhancementService)
                    .onAppear {
                        print("🔍 Creating ConfigurationSheet with mode: \(mode)")
                    }
                }
            }
        }
    }
}

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
