import SwiftUI

struct AudioInputPicker: View {
    @ObservedObject private var settings: AppSettings
    @StateObject private var inputDevices = AudioInputDeviceStore()

    private let isDisabled: Bool
    private let compact: Bool
    private let includeRefreshButton: Bool

    init(
        settings: AppSettings,
        isDisabled: Bool = false,
        compact: Bool = false,
        includeRefreshButton: Bool = false
    ) {
        _settings = ObservedObject(wrappedValue: settings)
        self.isDisabled = isDisabled
        self.compact = compact
        self.includeRefreshButton = includeRefreshButton
    }

    var body: some View {
        Group {
            if compact {
                compactPicker
            } else {
                settingsPicker
            }
        }
        .onAppear {
            inputDevices.refresh()
        }
    }

    private var compactPicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.50))

            Text("Input")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.42))

            inputMenu
                .frame(maxWidth: 250)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.055), lineWidth: 1)
        )
    }

    private var settingsPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Audio input")
                .font(.caption.weight(.semibold))

            HStack(spacing: 8) {
                inputMenu

                if includeRefreshButton {
                    Button("Refresh") {
                        inputDevices.refresh()
                    }
                    .pointingHandCursor()
                }
            }

            if let errorMessage = inputDevices.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if inputDevices.isMissingSelectedDevice(uid: settings.selectedInputDeviceUID) {
                Text("Selected input is not currently available.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var inputMenu: some View {
        Menu {
            Button {
                settings.selectedInputDeviceUID = ""
            } label: {
                menuItemLabel("Default system input", isSelected: selectedInputDeviceUID.isEmpty)
            }

            if !inputDevices.devices.isEmpty {
                Divider()
            }

            ForEach(inputDevices.devices) { device in
                Button {
                    settings.selectedInputDeviceUID = device.uid
                } label: {
                    menuItemLabel(device.name, isSelected: selectedInputDeviceUID == device.uid)
                }
            }

            if inputDevices.isMissingSelectedDevice(uid: settings.selectedInputDeviceUID) {
                Divider()

                Button {
                    settings.selectedInputDeviceUID = ""
                } label: {
                    Label("Reset missing input", systemImage: "exclamationmark.triangle")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedInputName)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(compact ? .white.opacity(0.40) : .secondary)
            }
            .font(compact ? .caption.weight(.medium) : .body)
            .foregroundStyle(compact ? .white.opacity(0.72) : .primary)
            .frame(maxWidth: compact ? 250 : .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .disabled(isDisabled)
        .pointingHandCursor(!isDisabled)
    }

    @ViewBuilder
    private func menuItemLabel(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private var selectedInputDeviceUID: String {
        settings.selectedInputDeviceUID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedInputName: String {
        guard !selectedInputDeviceUID.isEmpty else { return "Default system input" }

        if let device = inputDevices.devices.first(where: { $0.uid == selectedInputDeviceUID }) {
            return device.name
        }

        return "Missing input"
    }
}
