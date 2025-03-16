import SwiftUI
import SwiftData

struct TranscriptionHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var expandedTranscription: Transcription?
    @State private var selectedTranscriptions: Set<Transcription> = []
    @State private var showDeleteConfirmation = false
    
    // Pagination states
    @State private var displayedTranscriptions: [Transcription] = []
    @State private var isLoading = false
    @State private var hasMoreContent = true
    
    // Cursor-based pagination - track the last timestamp
    @State private var lastTimestamp: Date?
    private let pageSize = 20
    
    // Query for latest transcriptions (used for real-time updates)
    @Query(sort: \Transcription.timestamp, order: .reverse, animation: .default) 
    private var latestTranscriptions: [Transcription]
    
    // Cursor-based query descriptor
    private func cursorQueryDescriptor(after timestamp: Date? = nil) -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\Transcription.timestamp, order: .reverse)]
        )
        
        // Build the predicate based on search text and timestamp cursor
        if let timestamp = timestamp {
            if !searchText.isEmpty {
                descriptor.predicate = #Predicate<Transcription> { transcription in
                    (transcription.text.localizedStandardContains(searchText) ||
                    (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)) &&
                    transcription.timestamp < timestamp
                }
            } else {
                descriptor.predicate = #Predicate<Transcription> { transcription in
                    transcription.timestamp < timestamp
                }
            }
        } else if !searchText.isEmpty {
            descriptor.predicate = #Predicate<Transcription> { transcription in
                transcription.text.localizedStandardContains(searchText) ||
                (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)
            }
        }
        
        descriptor.fetchLimit = pageSize
        return descriptor
    }
    
    var body: some View {
        VStack(spacing: 0) {
            searchBar
            
            if displayedTranscriptions.isEmpty && !isLoading {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(displayedTranscriptions) { transcription in
                            TranscriptionCard(
                                transcription: transcription, 
                                isExpanded: expandedTranscription == transcription,
                                isSelected: selectedTranscriptions.contains(transcription),
                                onDelete: { deleteTranscription(transcription) },
                                onToggleSelection: { toggleSelection(transcription) }
                            )
                            .onTapGesture {
                                withAnimation {
                                    if expandedTranscription == transcription {
                                        expandedTranscription = nil
                                    } else {
                                        expandedTranscription = transcription
                                    }
                                }
                            }
                        }
                        
                        if hasMoreContent {
                            Button(action: {
                                loadMoreContent()
                            }) {
                                HStack(spacing: 8) {
                                    if isLoading {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                    Text(isLoading ? "Loading..." : "Load More")
                                        .font(.system(size: 14, weight: .medium))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(.windowBackgroundColor).opacity(0.4))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoading)
                            .padding(.top, 12)
                        }
                    }
                    .padding(24)
                }
                .padding(.vertical, 16)
            }
            
            if !selectedTranscriptions.isEmpty {
                selectionToolbar
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .alert("Delete Selected Items?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteSelectedTranscriptions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. Are you sure you want to delete \(selectedTranscriptions.count) item\(selectedTranscriptions.count == 1 ? "" : "s")?")
        }
        .onAppear {
            Task {
                await loadInitialContent()
            }
        }
        .onChange(of: searchText) { _, _ in
            Task {
                await resetPagination()
                await loadInitialContent()
            }
        }
        // Improved change detection for new transcriptions
        .onChange(of: latestTranscriptions) { oldValue, newValue in
            // Check if a new transcription was added
            if !newValue.isEmpty && (oldValue.isEmpty || newValue[0].id != oldValue[0].id) {
                // Only refresh if we're on the first page (no pagination cursor set)
                if lastTimestamp == nil {
                    Task {
                        await loadInitialContent()
                    }
                } else {
                    // If we're on a paginated view, show a notification or indicator that new content is available
                    // This could be a banner or button to "Show new transcriptions"
                    withAnimation {
                        // Reset pagination to show the latest content
                        Task {
                            await resetPagination()
                            await loadInitialContent()
                        }
                    }
                }
            }
        }
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search transcriptions", text: $searchText)
                .font(.system(size: 16, weight: .regular, design: .default))
                .textFieldStyle(PlainTextFieldStyle())
        }
        .padding(12)
        .background(Color(.windowBackgroundColor).opacity(0.4))
        .cornerRadius(10)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            Text("No transcriptions found")
                .font(.system(size: 24, weight: .semibold, design: .default))
            Text("Your history will appear here")
                .font(.system(size: 18, weight: .regular, design: .default))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor).opacity(0.4))
        .padding(24)
    }
    
    private var selectionToolbar: some View {
        HStack {
            Spacer()
            Button(action: {
                showDeleteConfirmation = true
            }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            
            if selectedTranscriptions.count < displayedTranscriptions.count {
                Button("Select All") {
                    Task {
                        await selectAllTranscriptions()
                    }
                }
                .buttonStyle(.bordered)
            } else {
                Button("Deselect All") {
                    selectedTranscriptions.removeAll()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .background(Color(.windowBackgroundColor).opacity(0.4))
    }
    
    private func loadInitialContent() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Reset cursor
            lastTimestamp = nil
            
            // Fetch initial page without a cursor
            let items = try modelContext.fetch(cursorQueryDescriptor())
            
            await MainActor.run {
                displayedTranscriptions = items
                // Update cursor to the timestamp of the last item
                lastTimestamp = items.last?.timestamp
                // If we got fewer items than the page size, there are no more items
                hasMoreContent = items.count == pageSize
            }
        } catch {
            print("Error loading transcriptions: \(error)")
        }
    }
    
    private func loadMoreContent() {
        guard !isLoading, hasMoreContent, let lastTimestamp = lastTimestamp else { return }
        
        Task {
            isLoading = true
            defer { isLoading = false }
            
            do {
                // Fetch next page using the cursor
                let newItems = try modelContext.fetch(cursorQueryDescriptor(after: lastTimestamp))
                
                await MainActor.run {
                    // Append new items to the displayed list
                    displayedTranscriptions.append(contentsOf: newItems)
                    // Update cursor to the timestamp of the last new item
                    self.lastTimestamp = newItems.last?.timestamp
                    // If we got fewer items than the page size, there are no more items
                    hasMoreContent = newItems.count == pageSize
                }
            } catch {
                print("Error loading more transcriptions: \(error)")
            }
        }
    }
    
    private func resetPagination() async {
        await MainActor.run {
            displayedTranscriptions = []
            lastTimestamp = nil
            hasMoreContent = true
            isLoading = false
        }
    }
    
    private func deleteTranscription(_ transcription: Transcription) {
        // First delete the audio file if it exists
        if let urlString = transcription.audioFileURL,
           let url = URL(string: urlString) {
            try? FileManager.default.removeItem(at: url)
        }
        
        modelContext.delete(transcription)
        if expandedTranscription == transcription {
            expandedTranscription = nil
        }
        
        // Remove from selection if selected
        selectedTranscriptions.remove(transcription)
        
        // Refresh the view
        Task {
            try? await modelContext.save()
            await loadInitialContent()
        }
    }
    
    private func deleteSelectedTranscriptions() {
        // Delete audio files and transcriptions
        for transcription in selectedTranscriptions {
            if let urlString = transcription.audioFileURL,
               let url = URL(string: urlString) {
                try? FileManager.default.removeItem(at: url)
            }
            modelContext.delete(transcription)
            if expandedTranscription == transcription {
                expandedTranscription = nil
            }
        }
        
        // Clear selection
        selectedTranscriptions.removeAll()
        
        // Save changes and refresh
        Task {
            try? await modelContext.save()
            await loadInitialContent()
        }
    }
    
    private func toggleSelection(_ transcription: Transcription) {
        if selectedTranscriptions.contains(transcription) {
            selectedTranscriptions.remove(transcription)
        } else {
            selectedTranscriptions.insert(transcription)
        }
    }
    
    // Modified function to select all transcriptions in the database
    private func selectAllTranscriptions() async {
        do {
            // Create a descriptor without pagination limits to get all IDs
            var allDescriptor = FetchDescriptor<Transcription>()
            
            // Apply search filter if needed
            if !searchText.isEmpty {
                allDescriptor.predicate = #Predicate<Transcription> { transcription in
                    transcription.text.localizedStandardContains(searchText) ||
                    (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)
                }
            }
            
            // For better performance, only fetch the IDs
            allDescriptor.propertiesToFetch = [\.id]
            
            // Fetch all matching transcriptions
            let allTranscriptions = try modelContext.fetch(allDescriptor)
            
            // Create a set of all visible transcriptions for quick lookup
            let visibleIds = Set(displayedTranscriptions.map { $0.id })
            
            // Add all transcriptions to the selection
            await MainActor.run {
                // First add all visible transcriptions directly
                selectedTranscriptions = Set(displayedTranscriptions)
                
                // Then add any non-visible transcriptions by ID
                for transcription in allTranscriptions {
                    if !visibleIds.contains(transcription.id) {
                        selectedTranscriptions.insert(transcription)
                    }
                }
            }
        } catch {
            print("Error selecting all transcriptions: \(error)")
        }
    }
}

struct CircularCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: {
            configuration.isOn.toggle()
        }) {
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(configuration.isOn ? .blue : .gray)
                .font(.system(size: 18))
        }
        .buttonStyle(.plain)
    }
}

struct TranscriptionCard: View {
    let transcription: Transcription
    let isExpanded: Bool
    let isSelected: Bool
    let onDelete: () -> Void
    let onToggleSelection: () -> Void
    @State private var showOriginalCopiedAlert = false
    @State private var showEnhancedCopiedAlert = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Selection checkbox in macOS style
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { _ in onToggleSelection() }
            ))
            .toggleStyle(CircularCheckboxStyle())
            .labelsHidden()
            
            VStack(alignment: .leading, spacing: 8) {
                // Header with date and duration
                HStack {
                    Text(transcription.timestamp, style: .date)
                        .font(.system(size: 14, weight: .medium, design: .default))
                        .foregroundColor(.secondary)
                    Spacer()
                    
                    Text(formatDuration(transcription.duration))
                        .font(.system(size: 14, weight: .medium, design: .default))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(6)
                }
                
                // Original text section
                VStack(alignment: .leading, spacing: 8) {
                    if isExpanded {
                        HStack {
                            Text("Original")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button {
                                copyToClipboard(transcription.text)
                                showOriginalCopiedAlert = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: showOriginalCopiedAlert ? "checkmark" : "doc.on.doc")
                                    Text(showOriginalCopiedAlert ? "Copied!" : "Copy")
                                }
                                .foregroundColor(showOriginalCopiedAlert ? .green : .blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(showOriginalCopiedAlert ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
                                )
                            }
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.2), value: showOriginalCopiedAlert)
                        }
                    }
                    
                    Text(transcription.text)
                        .font(.system(size: 15, weight: .regular, design: .default))
                        .lineLimit(isExpanded ? nil : 2)
                        .lineSpacing(2)
                }
                
                // Enhanced text section (only when expanded)
                if isExpanded, let enhancedText = transcription.enhancedText {
                    Divider()
                        .padding(.vertical, 8)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.blue)
                                Text("Enhanced")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.blue)
                            }
                            Spacer()
                            Button {
                                copyToClipboard(enhancedText)
                                showEnhancedCopiedAlert = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: showEnhancedCopiedAlert ? "checkmark" : "doc.on.doc")
                                    Text(showEnhancedCopiedAlert ? "Copied!" : "Copy")
                                }
                                .foregroundColor(showEnhancedCopiedAlert ? .green : .blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(showEnhancedCopiedAlert ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
                                )
                            }
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.2), value: showEnhancedCopiedAlert)
                        }
                        
                        Text(enhancedText)
                            .font(.system(size: 15, weight: .regular, design: .default))
                            .lineSpacing(2)
                    }
                }
                
                // Audio player (if available)
                if isExpanded, let urlString = transcription.audioFileURL,
                   let url = URL(string: urlString),
                   FileManager.default.fileExists(atPath: url.path) {
                    Divider()
                        .padding(.vertical, 8)
                    AudioPlayerView(url: url)
                }
                
                // Timestamp (only when expanded)
                if isExpanded {
                    HStack {
                        Text(transcription.timestamp, style: .time)
                            .font(.system(size: 14, weight: .regular, design: .default))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.windowBackgroundColor).opacity(0.4))
        )
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
        .contextMenu {
            if let enhancedText = transcription.enhancedText {
                Button {
                    copyToClipboard(enhancedText)
                    showEnhancedCopiedAlert = true
                } label: {
                    Label("Copy Enhanced", systemImage: "doc.on.doc")
                }
            }
            
            Button {
                copyToClipboard(transcription.text)
                showOriginalCopiedAlert = true
            } label: {
                Label("Copy Original", systemImage: "doc.on.doc")
            }
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .onChange(of: showOriginalCopiedAlert) { _, isShowing in
            if isShowing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showOriginalCopiedAlert = false
                }
            }
        }
        .onChange(of: showEnhancedCopiedAlert) { _, isShowing in
            if isShowing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showEnhancedCopiedAlert = false
                }
            }
        }
    }
    
    private func copyToClipboard(_ text: String) {
        let success = ClipboardManager.copyToClipboard(text)
        if !success {
            print("Failed to copy text to clipboard")
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
