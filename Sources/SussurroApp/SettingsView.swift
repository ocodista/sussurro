import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    @StateObject private var modelDownloader = ModelDownloadManager()
    @State private var selectedModelPreset = WhisperModelPreset.recommended
    @State private var showAdvancedPaths = false

    private var setupStatus: AppSetupStatus {
        AppSetupStatus.current(settings: settings)
    }

    private var selectedPresetURL: URL? {
        AppPaths.availableModelURL(for: selectedModelPreset)
    }

    private var selectedPresetIsAvailable: Bool {
        selectedPresetURL != nil
    }

    private var selectedPresetIsBundled: Bool {
        guard let selectedPresetURL else { return false }
        return AppPaths.isBundledModelURL(selectedPresetURL)
    }

    private var selectedPresetIsActive: Bool {
        guard let selectedPresetURL else { return false }
        return selectedPresetURL.path == settings.expandedModelPath
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                if !setupStatus.isReady {
                    setupNotice
                }

                audioInputCard
                transcriptionCard
                advancedPathsCard
                appDataCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 700, minHeight: 560)
        .background(SettingsTheme.windowBackground)
        .preferredColorScheme(.dark)
        .onAppear(perform: syncSelectedModelPreset)
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let logo = AppLogoImage.logo {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(SettingsTheme.primaryText)

                Text("Inputs, local transcription, and storage")
                    .font(.caption)
                    .foregroundStyle(SettingsTheme.secondaryText)
            }

            Spacer()

            SettingsStatusBadge(
                title: setupStatus.isReady ? "Ready" : "Needs attention",
                systemImage: setupStatus.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                color: setupStatus.isReady ? .green : .orange
            )
        }
    }

    private var setupNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.orange.opacity(0.95))
                .frame(width: 28, height: 28)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(setupNoticeTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SettingsTheme.primaryText)

                Text(setupNoticeDetail)
                    .font(.caption)
                    .foregroundStyle(SettingsTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if !setupStatus.isWhisperCLIReady {
                Button("Choose…", action: chooseWhisperCLIPath)
                    .buttonStyle(SettingsSecondaryButtonStyle())
                    .pointingHandCursor()

                Button("Reset Paths") {
                    settings.resetPathsToDefaults()
                    syncSelectedModelPreset()
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
                .pointingHandCursor()
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(0.16), lineWidth: 1)
        )
    }

    private var setupNoticeTitle: String {
        if !setupStatus.isWhisperCLIReady { return "Bundled whisper.cpp unavailable" }
        if !setupStatus.isModelReady { return "Model unavailable" }
        return "Setup needs attention"
    }

    private var setupNoticeDetail: String {
        if !setupStatus.isWhisperCLIReady {
            return "Sussurro includes whisper.cpp. Reset paths, reinstall Sussurro, or choose a custom whisper-cli executable."
        }

        if !setupStatus.isModelReady {
            return "The included model could not be found. Reset paths or reinstall Sussurro."
        }

        return "Check the settings below."
    }

    private var audioInputCard: some View {
        SettingsSectionCard(
            iconName: "mic",
            title: "Audio input",
            subtitle: "Choose the microphone used by the recorder."
        ) {
            AudioInputPicker(settings: settings, includeRefreshButton: true)
        }
    }

    private var transcriptionCard: some View {
        SettingsSectionCard(
            iconName: "captions.bubble",
            title: "Transcription",
            subtitle: "Runs locally with bundled whisper.cpp and an included Whisper model."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Model")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SettingsTheme.primaryText)
                        .frame(width: 72, alignment: .leading)

                    Picker("Model", selection: $selectedModelPreset) {
                        ForEach(WhisperModelPreset.allCases) { preset in
                            Text(preset.isRecommended ? "\(preset.displayName) · recommended" : preset.displayName)
                                .tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.regular)
                    .frame(maxWidth: 280, alignment: .leading)

                    SettingsStatusBadge(
                        title: selectedPresetIsAvailable ? modelAvailabilityBadgeTitle : "Missing",
                        systemImage: selectedPresetIsAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        color: selectedPresetIsAvailable ? .green : .orange
                    )

                    Spacer()

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

                Text(selectedModelPreset.setupDescription)
                    .font(.caption)
                    .foregroundStyle(SettingsTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Text(selectedPresetAvailabilityText)
                        .font(.caption2)
                        .foregroundStyle(selectedPresetIsAvailable ? .green.opacity(0.76) : SettingsTheme.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    if selectedPresetIsAvailable {
                        Button(selectedPresetIsActive ? "Active" : "Use Model") {
                            handlePrimaryModelAction()
                        }
                        .buttonStyle(SettingsSecondaryButtonStyle())
                        .disabled(selectedPresetIsActive)
                        .pointingHandCursor(!selectedPresetIsActive)
                    } else {
                        Button("Download Model") {
                            modelDownloader.download(selectedModelPreset, settings: settings)
                        }
                        .buttonStyle(SettingsPrimaryButtonStyle())
                        .disabled(modelDownloader.state.isDownloading)
                        .pointingHandCursor(!modelDownloader.state.isDownloading)
                    }
                }

                downloadStateView
            }
        }
    }

    private var advancedPathsCard: some View {
        SettingsSectionCard(
            iconName: "slider.horizontal.3",
            title: "Advanced paths",
            subtitle: "Most users do not need this. Override paths only if you want to use custom whisper.cpp or model files."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                SettingsCheckRow(
                    title: "whisper-cli",
                    detail: setupStatus.whisperCLIDetail,
                    isReady: setupStatus.isWhisperCLIReady
                )
                SettingsCheckRow(
                    title: "Model",
                    detail: setupStatus.modelDetail,
                    isReady: setupStatus.isModelReady
                )

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showAdvancedPaths.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showAdvancedPaths ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                        Text(showAdvancedPaths ? "Hide custom paths" : "Show custom paths")
                    }
                }
                .buttonStyle(SettingsSecondaryButtonStyle())
                .pointingHandCursor()

                if showAdvancedPaths {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsPathField(
                            title: "whisper-cli",
                            subtitle: "Executable used to run local transcription.",
                            placeholder: whisperCLIPlaceholder,
                            text: $settings.whisperCLIPath,
                            isReady: setupStatus.isWhisperCLIReady,
                            statusText: setupStatus.whisperCLIDetail,
                            chooseAction: chooseWhisperCLIPath
                        )

                        SettingsPathField(
                            title: "GGML model",
                            subtitle: "Model file passed to whisper-cli.",
                            placeholder: AppPaths.abbreviatedPath(AppPaths.preferredModelURL),
                            text: $settings.modelPath,
                            isReady: setupStatus.isModelReady,
                            statusText: setupStatus.modelDetail,
                            chooseAction: chooseModelPath
                        )

                        HStack {
                            Spacer()

                            Button("Reset to Defaults") {
                                settings.resetPathsToDefaults()
                                syncSelectedModelPreset()
                            }
                            .buttonStyle(SettingsSecondaryButtonStyle())
                            .pointingHandCursor()
                        }
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var appDataCard: some View {
        SettingsSectionCard(
            iconName: "externaldrive",
            title: "App data",
            subtitle: "Recordings stay local. Transcripts and retry history are stored in SQLite."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                SettingsDataRow(label: "Recordings", url: AppPaths.recordingsDirectory)
                SettingsDataRow(label: "History DB", url: AppPaths.historyDatabaseURL)
                SettingsDataRow(label: "Logs", url: AppPaths.logsDirectory)
                SettingsDataRow(label: "Downloaded models", url: AppPaths.modelsDirectory)

                HStack(spacing: 10) {
                    Button("Open App Data") {
                        NSWorkspace.shared.open(AppPaths.applicationSupportDirectory)
                    }
                    .buttonStyle(SettingsSecondaryButtonStyle())
                    .pointingHandCursor()

                    Button("Open Logs") {
                        NSWorkspace.shared.open(AppPaths.logsDirectory)
                    }
                    .buttonStyle(SettingsSecondaryButtonStyle())
                    .pointingHandCursor()

                    Spacer()
                }
                .padding(.top, 4)
            }
        }
    }

    private var modelAvailabilityBadgeTitle: String {
        selectedPresetIsBundled ? "Included" : "Ready"
    }

    private var selectedPresetAvailabilityText: String {
        if selectedPresetIsBundled {
            return "Included with Sussurro"
        }

        if selectedPresetURL != nil {
            return "Downloaded locally"
        }

        return "Optional download · \(selectedModelPreset.sizeDescription)"
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
            .foregroundStyle(SettingsTheme.secondaryText)
        case let .completed(message):
            SettingsInlineMessage(message: message, systemImage: "checkmark.circle.fill", color: .green)
        case let .failed(message):
            SettingsInlineMessage(message: message, systemImage: "exclamationmark.triangle.fill", color: .orange)
        }
    }

    private func handlePrimaryModelAction() {
        guard let selectedPresetURL else { return }
        settings.modelPath = selectedPresetURL.path
    }

    private func chooseWhisperCLIPath() {
        let panel = NSOpenPanel()
        panel.title = "Choose whisper-cli"
        panel.message = "Select the whisper-cli executable."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = AppPaths.defaultWhisperCLIURL()?.deletingLastPathComponent()
            ?? URL(fileURLWithPath: "/usr/local/bin", isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.whisperCLIPath = url.path
    }

    private func chooseModelPath() {
        let panel = NSOpenPanel()
        panel.title = "Choose GGML model"
        panel.message = "Select a GGML Whisper model file."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = AppPaths.modelsDirectory

        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.modelPath = url.path
        syncSelectedModelPreset()
    }

    private var whisperCLIPlaceholder: String {
        AppPaths.bundledWhisperCLIURL()
            .map(AppPaths.abbreviatedPath)
            ?? "Sussurro.app/Contents/MacOS/whisper-cli"
    }

    private func syncSelectedModelPreset() {
        let fileName = URL(fileURLWithPath: settings.expandedModelPath).lastPathComponent
        if let preset = WhisperModelPreset.preset(forFileName: fileName) {
            selectedModelPreset = preset
        }
    }
}

private enum SettingsTheme {
    static let windowBackground = Color(red: 0.055, green: 0.057, blue: 0.068)
    static let cardBackground = Color.white.opacity(0.045)
    static let primaryText = Color.white.opacity(0.88)
    static let secondaryText = Color.white.opacity(0.52)
    static let tertiaryText = Color.white.opacity(0.34)
}

private struct SettingsSectionCard<Content: View>: View {
    let iconName: String
    let title: String
    let subtitle: String
    let content: Content

    init(iconName: String, title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.iconName = iconName
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.64))
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(SettingsTheme.primaryText)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(SettingsTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct SettingsCheckRow: View {
    let title: String
    let detail: String
    let isReady: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isReady ? .green.opacity(0.90) : .orange.opacity(0.95))
                .frame(width: 16)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SettingsTheme.primaryText)
                .frame(width: 88, alignment: .leading)

            Text(detail)
                .font(.caption)
                .foregroundStyle(SettingsTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct SettingsPathField: View {
    let title: String
    let subtitle: String
    let placeholder: String
    @Binding var text: String
    let isReady: Bool
    let statusText: String
    let chooseAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SettingsTheme.primaryText)

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(SettingsTheme.tertiaryText)
                }

                Spacer()

                SettingsStatusBadge(
                    title: isReady ? "OK" : "Missing",
                    systemImage: isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    color: isReady ? .green : .orange
                )
            }

            HStack(spacing: 8) {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(SettingsTheme.primaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 31)
                    .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    )

                Button("Choose…", action: chooseAction)
                    .buttonStyle(SettingsSecondaryButtonStyle())
                    .pointingHandCursor()
            }

            Text(statusText)
                .font(.caption2)
                .foregroundStyle(isReady ? .green.opacity(0.72) : .orange.opacity(0.86))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

private struct SettingsDataRow: View {
    let label: String
    let url: URL

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SettingsTheme.primaryText)
                .frame(width: 116, alignment: .leading)

            Text(AppPaths.abbreviatedPath(url))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(SettingsTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer(minLength: 8)

            Button(action: reveal) {
                Image(systemName: "arrow.up.forward.square")
            }
            .buttonStyle(SettingsIconButtonStyle())
            .accessibilityLabel("Show \(label) in Finder")
            .pointingHandCursor()
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func reveal() {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}

private struct SettingsStatusBadge: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(color.opacity(0.95))
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(color.opacity(0.12), in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct SettingsInlineMessage: View {
    let message: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
            Text(message)
                .font(.caption)
                .lineLimit(2)
        }
        .foregroundStyle(color.opacity(0.95))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SettingsPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(configuration.isPressed ? Color.white.opacity(0.18) : Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

private struct SettingsSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.68))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(configuration.isPressed ? Color.white.opacity(0.10) : Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
    }
}

private struct SettingsIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.54))
            .frame(width: 26, height: 26)
            .background(configuration.isPressed ? Color.white.opacity(0.10) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}
