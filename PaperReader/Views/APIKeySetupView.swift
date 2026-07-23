import SwiftUI

/// Collects a personal Gemini API key: shown modally at first launch (not
/// dismissible until a key is saved) and from Settings to change the key.
struct APIKeySetupView: View {
    var canCancel = false

    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var isValidating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Paper Reader uses Google's Gemini API to clean up papers and generate audio. Everyone uses their own API key, so your usage stays on your own Google account.")
                        .font(.callout)
                    Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                        Label("Get a key at aistudio.google.com", systemImage: "key.fill")
                    }
                } footer: {
                    Text("Reading text works on the free tier. Generating audio uses Gemini's text-to-speech model, which requires billing to be enabled on your Google account.")
                }

                Section("Your API Key") {
                    TextField("Paste your key here", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button {
                        Task { await saveKey() }
                    } label: {
                        if isValidating {
                            HStack {
                                ProgressView()
                                Text("Checking key…")
                            }
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating)
                }
            }
            .navigationTitle("Gemini API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if canCancel {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    /// Round-trips a tiny request so a typo'd key is caught here instead of
    /// surfacing later as a failed paper.
    private func saveKey() async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isValidating = true
        errorMessage = nil
        defer { isValidating = false }

        do {
            try await GeminiClient().validate(apiKey: trimmed)
            APIKeyStore.save(trimmed)
            dismiss()
        } catch {
            errorMessage = "That key didn't work: \(error.localizedDescription)"
        }
    }
}
