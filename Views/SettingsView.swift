import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var apiKey = ""
    @State private var isValidating = false
    @State private var showAPIKey = false
    @State private var showDeleteConfirmation = false
    @State private var hasExistingKey = false
    @State private var isEditingKey = false

    private var audioDeviceManager: AudioDeviceManager { AudioDeviceManager.shared }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Audio Devices Section
                audioDevicesSection

                // API Configuration Section
                GroupBox("API Configuration") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("OpenAI API Key")
                            .font(.headline)

                        Text("Enter your OpenAI API key to use the app. Your key is stored securely in the system Keychain and never leaves your device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if hasExistingKey && !isEditingKey {
                            // Show masked display with edit button
                            HStack {
                                Text("sk-•••••••••••••••••••")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(Color.primary.opacity(0.05))
                                    .cornerRadius(6)
                                    .accessibilityLabel("API key")
                                    .accessibilityValue("Hidden. Key is saved securely.")

                                Button("Change") {
                                    isEditingKey = true
                                    apiKey = ""
                                }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Change API key")
                                .accessibilityHint("Double tap to enter a new API key")
                            }
                        } else {
                            // Editable field for new/changed key
                            HStack {
                                if showAPIKey {
                                    TextField("sk-...", text: $apiKey)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                } else {
                                    SecureField("sk-...", text: $apiKey)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                }

                                Button {
                                    showAPIKey.toggle()
                                } label: {
                                    Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(showAPIKey ? "Hide API key" : "Show API key")
                                .accessibilityHint("Double tap to toggle visibility")

                                if isEditingKey {
                                    Button("Cancel") {
                                        isEditingKey = false
                                        apiKey = ""
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }

                        if let error = appState.apiKeyError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        if !hasExistingKey || isEditingKey {
                            HStack {
                                Button("Save API Key") {
                                    Task {
                                        await saveAPIKey()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(apiKey.isEmpty || isValidating)

                                if isValidating {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }

                                Spacer()
                            }
                        }

                        if hasExistingKey && !isEditingKey {
                            HStack {
                                Spacer()

                                Button("Delete Key", role: .destructive) {
                                    showDeleteConfirmation = true
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Status Section
                GroupBox("Status") {
                    VStack(alignment: .leading, spacing: 8) {
                        if appState.hasAPIKey {
                            Label("API key configured", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("No API key configured", systemImage: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                        }

                        Link("Get an API key from OpenAI", destination: URL(string: "https://platform.openai.com/api-keys")!)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                // About Section
                GroupBox("About") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("App Version", value: "1.0.0")
                        LabeledContent("Build", value: "1")

                        Link(destination: URL(string: "https://platform.openai.com/docs")!) {
                            Label("OpenAI Documentation", systemImage: "book")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                // Privacy Section
                GroupBox("Privacy") {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Data stored locally", systemImage: "internaldrive")
                            Text("All interview data, transcripts, and drafts are stored only on your device using SwiftData.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Label("API key in Keychain", systemImage: "key")
                            Text("Your OpenAI API key is stored securely in the system Keychain with device-only access.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Label("OpenAI API calls", systemImage: "network")
                            Text("Voice and text data is sent to OpenAI for processing. Review OpenAI's privacy policy for details.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            loadExistingKey()
        }
        .confirmationDialog(
            "Delete API Key?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    await deleteAPIKey()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove your API key from the Keychain. You'll need to enter it again to use the app.")
        }
    }

    // MARK: - Audio Devices Section

    @ViewBuilder
    private var audioDevicesSection: some View {
        GroupBox("Audio Devices") {
            VStack(alignment: .leading, spacing: 16) {
                // Input Device Picker
                VStack(alignment: .leading, spacing: 4) {
                    Label("Microphone (Input)", systemImage: "mic")
                        .font(.headline)

                    if audioDeviceManager.inputDevices.isEmpty {
                        Text("No input devices available")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        Picker("Input Device", selection: Binding(
                            get: { audioDeviceManager.selectedInputDeviceID ?? "" },
                            set: { audioDeviceManager.selectedInputDeviceID = $0.isEmpty ? nil : $0 }
                        )) {
                            ForEach(audioDeviceManager.inputDevices) { device in
                                Text(device.name).tag(device.id)
                            }
                        }
                        .labelsHidden()
                        #if os(macOS)
                        .pickerStyle(.menu)
                        #endif
                    }
                }

                Divider()

                // Output Device Picker
                VStack(alignment: .leading, spacing: 4) {
                    Label("Speaker (Output)", systemImage: "speaker.wave.2")
                        .font(.headline)

                    if audioDeviceManager.outputDevices.isEmpty {
                        Text("No output devices available")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        Picker("Output Device", selection: Binding(
                            get: { audioDeviceManager.selectedOutputDeviceID ?? "" },
                            set: { audioDeviceManager.selectedOutputDeviceID = $0.isEmpty ? nil : $0 }
                        )) {
                            ForEach(audioDeviceManager.outputDevices) { device in
                                Text(device.name).tag(device.id)
                            }
                        }
                        .labelsHidden()
                        #if os(macOS)
                        .pickerStyle(.menu)
                        #endif
                    }
                }

                // Refresh button
                HStack {
                    Spacer()
                    Button {
                        audioDeviceManager.refreshDevices()
                    } label: {
                        Label("Refresh Devices", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Actions

    private func loadExistingKey() {
        Task {
            let keyExists = await appState.getAPIKey() != nil
            await MainActor.run {
                hasExistingKey = keyExists
                isEditingKey = false
                apiKey = ""
            }
        }
    }

    private func saveAPIKey() async {
        guard !apiKey.isEmpty else { return }

        await MainActor.run {
            isValidating = true
        }

        do {
            try await appState.saveAPIKey(apiKey)
            await MainActor.run {
                apiKey = ""
                hasExistingKey = true
                isEditingKey = false
            }
        } catch {
            // Error is handled by appState
        }

        await MainActor.run {
            isValidating = false
        }
    }

    private func deleteAPIKey() async {
        do {
            try await appState.deleteAPIKey()
            await MainActor.run {
                apiKey = ""
                hasExistingKey = false
                isEditingKey = false
            }
        } catch {
            // Handle error
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AppState.shared)
    }
}
