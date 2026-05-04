import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.title3.weight(.semibold))

            whisperCppSettings

            VStack(alignment: .leading, spacing: 6) {
                Text("App data")
                    .font(.caption.weight(.semibold))
                settingsPathRow("Models", AppPaths.modelsDirectory)
                settingsPathRow("Recordings", AppPaths.recordingsDirectory)
                settingsPathRow("Logs", AppPaths.logsDirectory)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Open App Data") {
                    NSWorkspace.shared.open(AppPaths.applicationSupportDirectory)
                }
                .pointingHandCursor()

                Button("Open Logs") {
                    NSWorkspace.shared.open(AppPaths.logsDirectory)
                }
                .pointingHandCursor()

                Spacer()

                Button("Reset Paths") {
                    settings.resetPathsToDefaults()
                }
                .pointingHandCursor()
            }

            Text("Tip: run scripts/download-model.sh turbo to install a local open-source Whisper model in the standard macOS app data folder.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 520, alignment: .leading)
    }

    private var whisperCppSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("whisper.cpp")
                    .font(.headline)

                SourceLinkButton(
                    kind: .github,
                    url: SourceLinks.whisperCppGitHubURL,
                    help: "Open whisper.cpp source on GitHub"
                )

                SourceLinkButton(
                    kind: .huggingFace,
                    url: SourceLinks.whisperCppHuggingFaceURL,
                    help: "Open whisper.cpp GGML models on Hugging Face"
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("whisper-cli")
                    .font(.caption.weight(.semibold))
                TextField("/opt/homebrew/bin/whisper-cli", text: $settings.whisperCLIPath)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("GGML model")
                    .font(.caption.weight(.semibold))
                TextField(AppPaths.abbreviatedPath(AppPaths.preferredModelURL), text: $settings.modelPath)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func settingsPathRow(_ label: String, _ url: URL) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label + ":")
                .frame(width: 76, alignment: .leading)
            Text(AppPaths.abbreviatedPath(url))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
