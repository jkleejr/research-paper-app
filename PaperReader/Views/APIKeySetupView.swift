import SwiftUI

/// Collects a personal Gemini API key: offered at first launch and from
/// Settings to change the key. Always dismissible — the library and imported
/// papers stay browsable without a key, and playback prompts for one.
struct APIKeySetupView: View {
    /// Label for the escape hatch: "Cancel" from Settings, "Not Now" at first run.
    var cancelTitle = "Cancel"

    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var isValidating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Paper Reader uses Google's Gemini API to clean up papers and read them aloud. Everyone brings their own API key, so your usage is billed to your own Google account and never to anyone else's.")
                        .font(.callout)
                    Link(destination: AppConfig.apiKeySignupURL) {
                        Label("Get a key at aistudio.google.com", systemImage: "key.fill")
                    }
                } footer: {
                    Text("Generating audio uses Gemini's text-to-speech model, which requires billing enabled on your Google account. A typical paper costs $1–2 of Google usage; a long one can reach $3. Text cleanup adds a few cents.")
                }

                Section {
                    Label("Your key is stored in the iOS Keychain on this device only.", systemImage: "lock.fill")
                        .font(.footnote)
                    Label("Text from the papers you import is sent to Google to be cleaned up and narrated. Nothing is sent anywhere else.", systemImage: "arrow.up.forward.app.fill")
                        .font(.footnote)
                    Link(destination: AppConfig.privacyPolicyURL) {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                            .font(.footnote)
                    }
                } header: {
                    Text("What Happens To Your Data")
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
                ToolbarItem(placement: .topBarLeading) {
                    Button(cancelTitle) { dismiss() }
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
