import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var openAIKey = ""
    @State private var showOpenAIKey = false
    @State private var validating = false

    private var audioDeviceManager: AudioDeviceManager { AudioDeviceManager.shared }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Audio Devices Section
                audioDevicesSection

                apiConfigurationSection
                statusSection
                aboutSection
                privacySection
            }
            .padding()
        }
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            loadKeys()
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
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - API Configuration

    @ViewBuilder
    private var apiConfigurationSection: some View {
        GroupBox("API Configuration") {
            VStack(alignment: .leading, spacing: 12) {
                providerKeyField(
                    title: "OpenAI API Key",
                    helper: "Stored securely in Keychain. Used for all agents.",
                    text: $openAIKey,
                    isSecure: !showOpenAIKey,
                    toggleSecure: { showOpenAIKey.toggle() },
                    isValid: appState.openAIValid,
                    errorText: appState.openAIError,
                    validateAction: { Task { await saveKey() } },
                    deleteAction: { Task { await deleteKey() } }
                )
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func providerKeyField(
        title: String,
        helper: String,
        text: Binding<String>,
        isSecure: Bool,
        toggleSecure: @escaping () -> Void,
        isValid: Bool,
        errorText: String?,
        validateAction: @escaping () -> Void,
        deleteAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(helper).font(.caption).foregroundStyle(.secondary)

            HStack {
                if isSecure {
                    SecureField("sk-...", text: text)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                } else {
                    TextField("sk-...", text: text)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                Button {
                    toggleSecure()
                } label: {
                    Image(systemName: isSecure ? "eye" : "eye.slash")
                }
                .buttonStyle(.borderless)
            }

            if let errorText, !(errorText.isEmpty) {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button("Save & Validate") { validateAction() }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.wrappedValue.isEmpty || validating)

                if validating {
                    ProgressView().scaleEffect(0.8)
                }

                Spacer()

                if isValid {
                    Button("Delete", role: .destructive) { deleteAction() }
                        .buttonStyle(.bordered)
                }
            }

            if isValid {
                Label("Key validated", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Status

    @ViewBuilder
    private var statusSection: some View {
        GroupBox("Status") {
            VStack(alignment: .leading, spacing: 8) {
                if appState.hasAPIKey {
                    Label("Ready with OpenAI", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("No valid API key configured", systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    // MARK: - About

    @ViewBuilder
    private var aboutSection: some View {
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
    }

    // MARK: - Privacy

    @ViewBuilder
    private var privacySection: some View {
        GroupBox("Privacy") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Data stored locally", systemImage: "internaldrive")
                    Text("All interview data, transcripts, and drafts are stored only on your device using SwiftData.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Label("API keys in Keychain", systemImage: "key")
                    Text("Your provider API keys are stored securely in the system Keychain with device-only access.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Label("Network calls", systemImage: "network")
                    Text("Voice and text data are sent to the selected provider for processing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers

    private func loadKeys() {
        openAIKey = appState.openAIKeyCached ?? ""
    }

    private func saveKey() async {
        validating = true
        await appState.saveAPIKey(openAIKey)
        validating = false
    }

    private func deleteKey() async {
        await appState.deleteAPIKey()
        loadKeys()
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AppState.shared)
    }
}
