import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingKeySetup = false

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
                    LabeledContent("Voice", value: AppConfig.ttsVoice)
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
