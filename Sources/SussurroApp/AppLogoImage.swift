import AppKit

enum AppLogoImage {
    static let logo: NSImage? = loadImage(named: "sussurro-logo", fileExtension: "png")
    static let appIcon: NSImage? = loadImage(named: "Sussurro", fileExtension: "icns") ?? logo

    private static func loadImage(named name: String, fileExtension: String) -> NSImage? {
        for url in candidateURLs(named: name, fileExtension: fileExtension) {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }

        return nil
    }

    private static func candidateURLs(named name: String, fileExtension: String) -> [URL] {
        let filename = "\(name).\(fileExtension)"
        var urls: [URL] = []

        if let bundleURL = Bundle.main.url(forResource: name, withExtension: fileExtension) {
            urls.append(bundleURL)
        }

        let sourceResourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
            .appendingPathComponent(filename)
        urls.append(sourceResourceURL)

        return urls
    }
}
