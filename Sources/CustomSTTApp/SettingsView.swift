import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("whisper-cli")
                    .font(.caption.weight(.semibold))
                TextField("/opt/homebrew/bin/whisper-cli", text: $settings.whisperCLIPath)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Model")
                    .font(.caption.weight(.semibold))
                TextField(AppPaths.abbreviatedPath(AppPaths.preferredModelURL), text: $settings.modelPath)
                    .textFieldStyle(.roundedBorder)
            }

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

                Button("Open Logs") {
                    NSWorkspace.shared.open(AppPaths.logsDirectory)
                }

                Spacer()

                Button("Reset Paths") {
                    settings.resetPathsToDefaults()
                }
            }

            Text("Tip: run scripts/download-model.sh turbo to install a local open-source Whisper model in the standard macOS app data folder.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 480, alignment: .leading)
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
