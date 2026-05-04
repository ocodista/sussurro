import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Include faster-whisper in the model race", isOn: $settings.useFasterWhisper)
                    .toggleStyle(.switch)

                Text("After you stop recording, Custom STT runs whisper.cpp and faster-whisper in parallel so you can compare speed and output side by side.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            whisperCppSettings

            if settings.useFasterWhisper {
                Divider()
                fasterWhisperSettings
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("App data")
                    .font(.caption.weight(.semibold))
                settingsPathRow("Models", AppPaths.modelsDirectory)
                settingsPathRow("Recordings", AppPaths.recordingsDirectory)
                settingsPathRow("Logs", AppPaths.logsDirectory)
                settingsPathRow("Caches", AppPaths.cacheDirectory)
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

            Text(settingsTip)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 520, alignment: .leading)
    }

    private var whisperCppSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("whisper.cpp")
                .font(.headline)

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

    private var fasterWhisperSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("faster-whisper")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Python executable")
                    .font(.caption.weight(.semibold))
                TextField(AppPaths.abbreviatedPath(AppPaths.fasterWhisperVirtualEnvironmentPythonURL), text: $settings.fasterWhisperPythonPath)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Model")
                    .font(.caption.weight(.semibold))
                TextField(AppPaths.defaultFasterWhisperModelName, text: $settings.fasterWhisperModel)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Device")
                    .font(.caption.weight(.semibold))
                Picker("Device", selection: $settings.fasterWhisperDevice) {
                    Text("Auto").tag("auto")
                    Text("CPU").tag("cpu")
                    Text("CUDA").tag("cuda")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        }
    }

    private var settingsTip: String {
        if settings.useFasterWhisper {
            return "Tip: run scripts/install-faster-whisper.sh to create the app-managed Python environment. The selected model downloads into ~/Library/Application Support/CustomSTT/Models/FasterWhisper on first use; press Stop to cancel a long first download."
        }

        return "Tip: run scripts/download-model.sh turbo to install a local open-source Whisper model in the standard macOS app data folder."
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
