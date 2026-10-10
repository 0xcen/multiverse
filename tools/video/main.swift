import SwiftUI

// Entry point for the launch film. Usage (from the repo root, see render.sh):
//   launch-video frames <dir> | still <n> <file> | same <n> | audio <file.wav>

@MainActor func renderFrame(_ n: Int) -> CGImage {
    let renderer = ImageRenderer(content: Frame(n: n))
    // MV_SCALE=2 renders 3840×2160.
    renderer.scale = Double(ProcessInfo.processInfo.environment["MV_SCALE"] ?? "1") ?? 1
    return renderer.cgImage!
}

@MainActor func pngData(_ image: CGImage) -> Data {
    NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

@main
struct LaunchVideo {
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let args = CommandLine.arguments
        MainActor.assumeIsolated {
            switch args.dropFirst().first {
            case "frames":
                let dir = args[2]
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                for n in 0..<frameCount {
                    autoreleasepool {
                        try! pngData(renderFrame(n)).write(to: URL(fileURLWithPath: String(format: "%@/%04d.png", dir, n)))
                    }
                }
                print("frames \(frameCount)")
            case "still":
                try! pngData(renderFrame(Int(args[2])!)).write(to: URL(fileURLWithPath: args[3]))
            case "same":
                let n = Int(args[2])!
                let same = pngData(renderFrame(n)) == pngData(renderFrame(n))
                print(same ? "same \(n)" : "DIFFERENT \(n)")
                exit(same ? 0 : 1)
            case "audio":
                writeWAV(filmSoundtrack(), to: args[2])
                print("audio \(T.duration)s")
            case "frames-count":
                print(frameCount)
            default:
                print("usage: launch-video frames <dir> | still <n> <file> | same <n> | audio <file.wav>")
            }
        }
    }
}
