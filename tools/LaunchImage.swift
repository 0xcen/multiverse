import SwiftUI

// Renders docs/launch.png (16:9) and docs/launch-4x3.png in the Carbon style.
// Build from the repo root:
//   swiftc -parse-as-library -D SNAPSHOT Sources/*.swift tools/Carbon.swift tools/LaunchImage.swift -o /tmp/launch-image
//   /tmp/launch-image && sips -z 1350 2400 docs/launch.png && sips -z 1200 1600 docs/launch-4x3.png

private let apps = ["Claude", "ChatGPT", "Cursor"]

struct LaunchWide: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Carbon.bg
            HStack(alignment: .top, spacing: 56) {
                VStack(alignment: .leading, spacing: 0) {
                    CarbonBrand(size: 44)
                    Spacer().frame(height: 56)
                    Headline(lines: ["Same apps.", "Different", "universes."], size: 124)
                    Spacer().frame(height: 30)
                    Text("Separate logins.\nEvery link in the right browser.")
                        .font(.system(size: 36))
                        .tracking(-0.8)
                        .foregroundStyle(Carbon.muted)
                        .fixedSize()
                }
                .frame(width: 700, alignment: .leading)

                VStack(spacing: 24) {
                    UniversePanel(name: "Work", dot: Carbon.ivory, apps: apps, ivory: false,
                                  browser: "Google Chrome", browserLabel: "Chrome", iconSize: 66, fontSize: 24)
                    UniversePanel(name: "Personal", dot: Carbon.olive, apps: apps, ivory: true,
                                  browser: "Dia", browserLabel: "Personal Dia", iconSize: 66, fontSize: 24)
                    UniversePanel(name: "Side project", dot: Carbon.gray, apps: apps, ivory: false,
                                  browser: "Dia", browserLabel: "Side project Dia", iconSize: 66, fontSize: 24)
                }
                .frame(width: 700)
                .padding(.top, 36)
            }
            .padding(.leading, 84).padding(.top, 76)

            VStack(spacing: 0) {
                Rectangle().fill(Carbon.border).frame(height: 1)
                HStack(spacing: 0) {
                    fact("Free & open source")
                    Rectangle().fill(Carbon.border).frame(width: 1, height: 28)
                    fact("macOS 14+")
                    Rectangle().fill(Carbon.border).frame(width: 1, height: 28)
                    fact("Set up by your agent")
                }
                .frame(height: 96)
            }
            .padding(.horizontal, 60)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: 1600, height: 900)
    }

    private func fact(_ text: String) -> some View {
        Text(text).font(.system(size: 22)).foregroundStyle(Carbon.muted).frame(maxWidth: .infinity)
    }
}

struct LaunchFourThree: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CarbonBrand(size: 50)
            Spacer().frame(height: 36)
            Headline(lines: ["Same apps.", "Separate worlds."], size: 140)
            Spacer().frame(height: 40)
            VStack(spacing: 22) {
                UniversePanel(name: "Work", dot: Carbon.ivory, apps: apps, ivory: false,
                              browser: "Google Chrome", browserLabel: "Chrome", iconSize: 120, fontSize: 36)
                UniversePanel(name: "Personal", dot: Carbon.olive, apps: apps, ivory: true,
                              browser: "Dia", browserLabel: "Personal Dia", iconSize: 120, fontSize: 36)
            }
            Spacer(minLength: 30)
            Text("Separate logins. The right browser.")
                .font(.system(size: 36)).tracking(-0.8).foregroundStyle(Carbon.muted)
        }
        .padding(.horizontal, 84).padding(.top, 60).padding(.bottom, 70)
        .frame(width: 1600, height: 1200, alignment: .topLeading)
        .background(Carbon.bg)
    }
}

@main
struct RenderLaunchImages {
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            renderPNG(LaunchWide(), to: "docs/launch.png")
            renderPNG(LaunchFourThree(), to: "docs/launch-4x3.png")
        }
    }
}
