import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    @StateObject private var modelDownloader = ModelDownloadManager()
    @State private var selectedModelPreset = WhisperModelPreset.recommended

    private var setupStatus: AppSetupStatus {
        AppSetupStatus.current(settings: settings)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(.title3.weight(.semibold))

                setupAssistant

                AudioInputPicker(settings: settings, includeRefreshButton: true)

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
            }
            .padding(20)
            .frame(width: 600, alignment: .leading)
        }
        .frame(width: 640, height: 640)
    }

    private var setupAssistant: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("First-time setup")
                    .font(.headline)

                Spacer()

                Text(setupStatus.isReady ? "Ready" : "Needs setup")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(setupStatus.isReady ? .green : .orange)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background((setupStatus.isReady ? Color.green : Color.orange).opacity(0.12), in: Capsule())
            }

            Text("Sussurro transcribes locally with whisper.cpp. It needs the whisper-cli executable and one GGML Whisper model before recording can turn into text.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                setupStatusRow(
                    title: "whisper-cli",
                    isReady: setupStatus.isWhisperCLIReady,
                    detail: setupStatus.whisperCLIDetail
                )
                setupStatusRow(
                    title: "GGML model",
                    isReady: setupStatus.isModelReady,
                    detail: setupStatus.modelDetail
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Picker("Model preset", selection: $selectedModelPreset) {
                    ForEach(WhisperModelPreset.allCases) { preset in
                        Text(preset.isRecommended ? "\(preset.displayName) · recommended" : preset.displayName)
                            .tag(preset)
                    }
                }
                .pickerStyle(.menu)

                Text(selectedModelPreset.setupDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                downloadStateView

                HStack(spacing: 10) {
                    Button(downloadButtonTitle) {
                        modelDownloader.download(selectedModelPreset, settings: settings)
                    }
                    .disabled(modelDownloader.state.isDownloading)
                    .pointingHandCursor(!modelDownloader.state.isDownloading)

                    Button("Use Local Path") {
                        settings.modelPath = AppPaths.modelURL(for: selectedModelPreset).path
                    }
                    .pointingHandCursor()

                    Button("Copy Setup Command") {
                        copyToClipboard(WhisperSetupCommands.fullInstallCommand(for: selectedModelPreset))
                    }
                    .pointingHandCursor()
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
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

    private var downloadButtonTitle: String {
        if FileManager.default.fileExists(atPath: AppPaths.modelURL(for: selectedModelPreset).path) {
            return "Use Selected Model"
        }

        return "Download Model"
    }

    @ViewBuilder
    private var downloadStateView: some View {
        switch modelDownloader.state {
        case .idle:
            EmptyView()
        case let .downloading(message):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(message)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case let .completed(message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.green)
        case let .failed(message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func setupStatusRow(title: String, isReady: Bool, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isReady ? .green : .orange)
                .frame(width: 16)

            Text(title)
                .font(.caption.weight(.semibold))
                .frame(width: 86, alignment: .leading)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func settingsPathRow(_ label: String, _ url: URL) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label + ":")
                .frame(width: 86, alignment: .leading)
            Text(AppPaths.abbreviatedPath(url))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
