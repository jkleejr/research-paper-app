import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingKeySetup = false
    @State private var showingKeyRemoval = false
    @State private var voice = AppConfig.ttsVoice

    private var hasKey: Bool { AppConfig.geminiAPIKey != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("API Key") {
                        if hasKey {
                            Label("Configured", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .labelStyle(.titleAndIcon)
                        } else {
                            Label("Missing", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    Button(hasKey ? "Change API Key…" : "Add API Key…") {
                        showingKeySetup = true
                    }
                    if hasKey {
                        Button("Remove API Key", role: .destructive) {
                            showingKeyRemoval = true
                        }
                    }
                    LabeledContent("Text model", value: AppConfig.textModel)
                    LabeledContent("Voice model", value: AppConfig.ttsModel)
                } header: {
                    Text("Gemini API")
                } footer: {
                    Text("Your key is stored in this device's Keychain. Paper text is sent to Google's Gemini API and billed to your own Google account.")
                }

                Section {
                    Picker("Voice", selection: $voice) {
                        ForEach(AppConfig.voiceOptions, id: \.name) { option in
                            Text("\(option.name) · \(option.style)").tag(option.name)
                        }
                    }
                    .onChange(of: voice) { AppConfig.ttsVoice = voice }
                } header: {
                    Text("Narration")
                } footer: {
                    Text("The voice applies to audio generated from now on. Papers keep audio that was already generated, so changing mid-paper mixes voices.")
                }

                Section("About") {
                    LabeledContent("Version", value: AppConfig.versionString)
                    Link(destination: AppConfig.privacyPolicyURL) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    Link(destination: AppConfig.supportURL) {
                        Label("Support", systemImage: "questionmark.circle")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingKeySetup) {
                APIKeySetupView()
            }
            .confirmationDialog("Remove your API key from this device?",
                                isPresented: $showingKeyRemoval,
                                titleVisibility: .visible) {
                Button("Remove Key", role: .destructive) { APIKeyStore.delete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Papers and audio already generated stay on your device. You'll need a key again to process new papers.")
            }
        }
    }
}
