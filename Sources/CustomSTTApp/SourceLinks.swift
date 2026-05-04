import AppKit
import SwiftUI

enum SourceLinks {
    static let whisperCppGitHubURL = URL(string: "https://github.com/ggml-org/whisper.cpp")!
    static let whisperCppHuggingFaceURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp")!
}

enum SourceLinkKind {
    case github
    case huggingFace
}

struct SourceLinkButton: View {
    let kind: SourceLinkKind
    let url: URL
    let help: String

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            icon
                .frame(width: 24, height: 20)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(help)
    }

    @ViewBuilder
    private var icon: some View {
        switch kind {
        case .github:
            if let image = GitHubMarkImage.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .clipShape(Circle())
            } else {
                Text("GH")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.84))
            }
        case .huggingFace:
            Text("🤗")
                .font(.system(size: 12))
        }
    }
}

private enum GitHubMarkImage {
    static let image: NSImage? = {
        guard let data = Data(base64Encoded: base64PNG) else { return nil }
        return NSImage(data: data)
    }()

    private static let base64PNG = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAAXNSR0IArs4c6QAAAERlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAIKADAAQAAAABAAAAIAAAAACshmLzAAAD7ElEQVRIDdVVW0iTYRhu7uROHjbXsmZuc1ueuvFCWiuooINkZdflChLdKoLELuzK20rB1LLsIm0Z1FWxga51JRSCocZGnqYo6pq6EgWnbjp75Ief7//dVhd50c8G7/u9z/M+3/t+J87W1tae3fySdjP5du7/X4D3Ny1aX1/3+XwTExM/g0HgFQqFTqfTGwxCofCP9D8IzMzMvLbbnU7nxPh4KBSKRqPbbU1KEovF0DhfWlpusajV6kQy2EUxP+R60daWazRKxWJ5WtrejAyVUkn/4GIQoUMGQ9vz5wDHTIJBDv479dfW1u7V1Lzq6ODz+Txeoio3NzfD4XB5efmjhgaRSLQzVQyBjY2NO7dv2+325ORkdJ/L5QoEAg6HwyJjZkgNAawEJnTl6tWWJ092zoZbV1fHYrY0Nzc2NoKm1+vvVlfzuNzJyUlqAZAU3YhEIpTwyVOnblRU+Gdnl5aWBgYGpFLpEZOJlY1dwcjIyJnTp1dDIUyqymp9VF8PwkeXq7e3Ny8vL0OphBsMBoe+fy8uLj5XUgL3fm0t5oRy0SKX252bm0tqsPv7rLV18dcvbBKA6F145uxZ/EgaaaOBcLG1FhcXW58+fdzUREYZJ3lhYaG7q4vOi8JJaDx7eXmZCoHo6u6en58nkQyBr319gUAAq4pGy+Vym81GQuPZVptNqVSCAuLc3BySkEiGgNfrxa5AOBIOm0ym/IICEhrPNhqNZrMZOwoA0L0eD4lkCPj9fmozbkaj2RoNiUtsA4wKgMFu/hEIkGCGACYOCBWmZkRCE9gkmLRBYQhIZTLqYKObU1NTCTKyQjgooGAQdJlMRkYZAlqtlorhhvg2ODg9PU1C49lo7EB/PygUgE5CuQyBoqIinBcqgP3w8MGDeEnJccCwNXEOMAg6kpDR7aLob3V19djRo2kpKYcLCwvy8yUi0S2bbdznowEsA4/ErZs301NTqVsW9yvoSELCGAII4CQL+fzLZWXDw8PXLBY+l6vTaC5duPCms5Okwb1YWqrVaFJlMvoOx+0NOgmDzRbAsTxuNgt4vOsWC47+yRMnREIh3A/v35NMh8OB+pQKBZ0ddYMIOgmLIYChL58/79+3L0Ui+eR2o16nw9HT04MblGTi+TyoVtOvUIZcfiAzE0QSQ9nsCqjRd2/fKtLT9Tpd+8uXo6OjQ0NDuF9JMgSys7IoAbQedYBCAmg7tgDCeIcNOTlYA2TBZFlLDReDaJFMIsGzCjCdkWXEFQAO07RWVmaqVKhmbGyMZMLF4H6VylpVBRgZYtmJBCiox+PpaG9fWVkhmXAxiBA5GNNmv2iMM/IvHMZJ/hcJ2Tn+f4HflqqF5TLvssAAAAAASUVORK5CYII="
}
