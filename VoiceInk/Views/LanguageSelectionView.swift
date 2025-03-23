import SwiftUI

// Define a display mode for flexible usage
enum LanguageDisplayMode {
    case full      // For settings page with descriptions
    case menuItem  // For menu bar with compact layout
}

struct LanguageSelectionView: View {
    @ObservedObject var whisperState: WhisperState
    @AppStorage("SelectedLanguage") private var selectedLanguage: String = "en"
    // Add display mode parameter with full as the default
    var displayMode: LanguageDisplayMode = .full
    
    let languages = [
        "auto": "Auto-detect",
        "af": "Afrikaans",
        "am": "Amharic",
        "ar": "Arabic",
        "as": "Assamese",
        "az": "Azerbaijani",
        "ba": "Bashkir",
        "be": "Belarusian",
        "bg": "Bulgarian",
        "bn": "Bengali",
        "bo": "Tibetan",
        "br": "Breton",
        "bs": "Bosnian",
        "ca": "Catalan",
        "cs": "Czech",
        "cy": "Welsh",
        "da": "Danish",
        "de": "German",
        "el": "Greek",
        "en": "English",
        "es": "Spanish",
        "et": "Estonian",
        "eu": "Basque",
        "fa": "Persian",
        "fi": "Finnish",
        "fo": "Faroese",
        "fr": "French",
        "ga": "Irish",
        "gl": "Galician",
        "gu": "Gujarati",
        "ha": "Hausa",
        "he": "Hebrew",
        "hi": "Hindi",
        "hr": "Croatian",
        "ht": "Haitian Creole",
        "hu": "Hungarian",
        "hy": "Armenian",
        "id": "Indonesian",
        "is": "Icelandic",
        "it": "Italian",
        "ja": "Japanese",
        "jw": "Javanese",
        "ka": "Georgian",
        "kk": "Kazakh",
        "km": "Khmer",
        "kn": "Kannada",
        "ko": "Korean",
        "la": "Latin",
        "lb": "Luxembourgish",
        "ln": "Lingala",
        "lo": "Lao",
        "lt": "Lithuanian",
        "lv": "Latvian",
        "mg": "Malagasy",
        "mi": "Maori",
        "mk": "Macedonian",
        "ml": "Malayalam",
        "mn": "Mongolian",
        "mr": "Marathi",
        "ms": "Malay",
        "mt": "Maltese",
        "my": "Myanmar",
        "ne": "Nepali",
        "nl": "Dutch",
        "nn": "Norwegian Nynorsk",
        "no": "Norwegian",
        "oc": "Occitan",
        "pa": "Punjabi",
        "pl": "Polish",
        "ps": "Pashto",
        "pt": "Portuguese",
        "ro": "Romanian",
        "ru": "Russian",
        "sa": "Sanskrit",
        "sd": "Sindhi",
        "si": "Sinhala",
        "sk": "Slovak",
        "sl": "Slovenian",
        "sn": "Shona",
        "so": "Somali",
        "sq": "Albanian",
        "sr": "Serbian",
        "su": "Sundanese",
        "sv": "Swedish",
        "sw": "Swahili",
        "ta": "Tamil",
        "te": "Telugu",
        "tg": "Tajik",
        "th": "Thai",
        "tk": "Turkmen",
        "tl": "Tagalog",
        "tr": "Turkish",
        "tt": "Tatar",
        "ug": "Uyghur",
        "uk": "Ukrainian",
        "ur": "Urdu",
        "uz": "Uzbek",
        "vi": "Vietnamese",
        "yi": "Yiddish",
        "yo": "Yoruba",
        "zh": "Chinese"
    ]
    
    private func updateLanguage(_ language: String) {
        // Update UI state - the UserDefaults updating is now automatic with @AppStorage
        selectedLanguage = language
        
        // Post notification for language change
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
    }
    
    // Function to check if current model is multilingual
    private func isMultilingualModel() -> Bool {
        guard let currentModel = whisperState.currentModel,
               let predefinedModel = PredefinedModels.models.first(where: { $0.name == currentModel.name }) else {
            return false
        }
        return predefinedModel.language == "Multilingual"
    }
    
    // Get the display name of the current language
    private func currentLanguageDisplayName() -> String {
        return languages[selectedLanguage] ?? "Unknown"
    }
    
    var body: some View {
        switch displayMode {
        case .full:
            fullView
        case .menuItem:
            menuItemView
        }
    }
    
    // The original full view layout for settings page
    private var fullView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcription Language")
                .font(.headline)
            
            if let currentModel = whisperState.currentModel,
               let predefinedModel = PredefinedModels.models.first(where: { $0.name == currentModel.name }) {
                
                if predefinedModel.language == "Multilingual" {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Select Language", selection: $selectedLanguage) {
                            ForEach(languages.sorted(by: { $0.value < $1.value }), id: \.key) { key, value in
                                Text(value).tag(key)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: selectedLanguage) { newValue in
                            updateLanguage(newValue)
                        }
                        
                        Text("Current model: \(predefinedModel.displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("This model supports multiple languages. You can choose auto-detect or select a specific language.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    // For English-only models, force set language to English
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Language: English")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        
                        Text("Current model: \(predefinedModel.displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("This is an English-optimized model and only supports English transcription.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .onAppear {
                        // Ensure English is set when viewing English-only model
                        updateLanguage("en")
                    }
                }
            } else {
                Text("No model selected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    // New compact view for menu bar
    private var menuItemView: some View {
        Group {
            if isMultilingualModel() {
                Menu {
                    ForEach(languages.sorted(by: { $0.value < $1.value }), id: \.key) { key, value in
                        Button {
                            updateLanguage(key)
                        } label: {
                            HStack {
                                Text(value)
                                if selectedLanguage == key {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text("Language: \(currentLanguageDisplayName())")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                    }
                }
            } else {
                // For English-only models
                Button {
                    // Do nothing, just showing info
                } label: {
                    Text("Language: English (only)")
                        .foregroundColor(.secondary)
                }
                .disabled(true)
                .onAppear {
                    // Ensure English is set for English-only models
                    updateLanguage("en")
                }
            }
        }
    }
}
