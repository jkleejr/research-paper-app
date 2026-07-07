import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Gemini API") {
                    LabeledContent("API Key") {
                        if AppConfig.geminiAPIKey != nil {
                            Label("Configured", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .labelStyle(.titleAndIcon)
                        } else {
                            Label("Missing", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    LabeledContent("Text model", value: AppConfig.textModel)
                    LabeledContent("Voice model", value: AppConfig.ttsModel)
                    LabeledContent("Voice", value: AppConfig.ttsVoice)
                }
                if AppConfig.geminiAPIKey == nil {
                    Section {
                        Text("Add your key to PaperReader/Support/Secrets.xcconfig and rebuild. Get a free key at aistudio.google.com/apikey.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
        }
    }
}
