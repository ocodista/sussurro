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

            picker
                .labelsHidden()
                .frame(maxWidth: 230)

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
                picker

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

    private var picker: some View {
        Picker("Audio input", selection: $settings.selectedInputDeviceUID) {
            Text("Default system input").tag("")

            ForEach(inputDevices.devices) { device in
                Text(device.name).tag(device.uid)
            }

            if inputDevices.isMissingSelectedDevice(uid: settings.selectedInputDeviceUID) {
                Text("Missing input").tag(settings.selectedInputDeviceUID)
            }
        }
        .pickerStyle(.menu)
        .disabled(isDisabled)
    }
}
