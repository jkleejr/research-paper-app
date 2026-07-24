import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingKeySetup = false
    @State private var voice = AppConfig.ttsVoice

    private var hasKey: Bool { AppConfig.geminiAPIKey != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Gemini API") {
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
                    LabeledContent("Text model", value: AppConfig.textModel)
                    LabeledContent("Voice model", value: AppConfig.ttsModel)
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
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingKeySetup) {
                APIKeySetupView(canCancel: true)
            }
        }
    }
}
