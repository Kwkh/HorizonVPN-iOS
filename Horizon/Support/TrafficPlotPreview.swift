#if DEBUG
import SwiftUI

/// An explicitly labeled, opt-in rendering harness. Never reads a subscription or starts a VPN.
struct TrafficPlotPreview: View {
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("曲线渲染样例").font(.largeTitle.bold())
            Text("虚构数据 · 无网络请求").foregroundStyle(.orange)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let end = floor(ProcessInfo.processInfo.systemUptime)
                let points = (0...68).map { i -> TrafficPoint in
                    let t = end - 68 + Double(i)
                    return TrafficPoint(id: t, date: Date(),
                        upload: 230 + 200 * sin(t * 0.7),
                        download: 400 + 300 * sin(t * 0.5), segment: 0)
                }
                ScrollingTrafficPlot(points: points,
                    uploadColor: Color(red: 1, green: 0.24, blue: 0.32),
                    downloadColor: ClashStyle.mint, running: phase == .active, reduceMotion: reduced, ceiling: 1000)
                    .frame(height: 90)
            }
            Text("60s").foregroundStyle(.secondary)
            Spacer()
        }.padding(28).padding(.top, 30).preferredColorScheme(.dark)
    }
}
#endif
