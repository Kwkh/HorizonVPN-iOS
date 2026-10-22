import SwiftUI
import CoreText
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Single-line lettering gives each pen stroke its own direction and easing.
/// It remains vector geometry after drawing, avoiding a swap back to a font.
struct HorizonWelcomeWordmark: View {
    static let duration = strokes.map { $0.start + $0.duration }.max() ?? 0
    let revealed: Bool
    let active: Bool
    let fontSize: CGFloat
    let completed: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var elapsed: TimeInterval = 0
    @State private var startedAt: Date?

    private var playing: Bool { revealed && active && scenePhase == .active && !reduceMotion }

    var body: some View {
        // Shape the original spaced system text once per body update, not per frame.
        let layout = Self.letterLayout(fontSize: fontSize)
        return TimelineView(.animation(minimumInterval: 1 / 60, paused: startedAt == nil)) { timeline in
            let time = min(Self.duration, elapsed + (startedAt.map { timeline.date.timeIntervalSince($0) } ?? 0))
            GeometryReader { geometry in
                let scale = min(1, geometry.size.width / layout.width)
                let size = CGSize(width: layout.width * scale, height: layout.height * scale)
                ZStack {
                    ForEach(Self.strokes.indices, id: \.self) { index in
                        let stroke = Self.strokes[index]
                        let fraction = min(1, max(0, (time - stroke.start) / stroke.duration))
                        // A longer quartic tail lingers near each stroke's endpoint.
                        let progress = 1 - pow(1 - fraction, 4)
                        stroke.path
                            .trimmedPath(from: 0, to: reduceMotion && revealed ? 1 : progress)
                            .applying(layout.transforms[stroke.letter])
                            .applying(CGAffineTransform(scaleX: scale, y: scale))
                            .stroke(.primary, style: StrokeStyle(lineWidth: layout.lineWidth * scale,
                                                                 lineCap: .round, lineJoin: .round))
                    }
                }
                .frame(width: size.width, height: size.height)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
        .frame(height: fontSize * 1.2)
        .opacity(revealed ? 1 : 0)
        .animation(reduceMotion ? .easeOut(duration: 0.18) : nil, value: revealed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("HORIZON")
        .onChange(of: playing, initial: true) { _, playing in
            if playing, elapsed < Self.duration {
                startedAt = Date()
            } else if let start = startedAt {
                elapsed = min(Self.duration, elapsed + Date().timeIntervalSince(start))
                startedAt = nil
            }
        }
        .onChange(of: reduceMotion && revealed, initial: true) { _, simplified in
            if simplified {
                elapsed = Self.duration
                startedAt = nil
                completed()
            }
        }
        .task(id: startedAt) {
            guard let start = startedAt else { return }
            do { try await Task.sleep(for: .seconds(max(0, Self.duration - elapsed))) }
            catch { return }
            guard !Task.isCancelled, startedAt == start else { return }
            elapsed = Self.duration
            startedAt = nil
            completed()
        }
    }

    private struct Stroke {
        let path: Path
        let letter: Int
        let start: TimeInterval
        let duration: TimeInterval
    }

    private struct LetterLayout {
        let width: CGFloat
        let height: CGFloat
        let lineWidth: CGFloat
        let transforms: [CGAffineTransform]
    }

    /// Preserve the original "H O R I Z O N" + tracking(1.5) glyph positions.
    /// A narrow I must retain its own advance, rather than a hand-spaced wide cell.
    private static func letterLayout(fontSize: CGFloat) -> LetterLayout {
        #if os(macOS)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .ultraLight)
        #else
        let font = UIFont.systemFont(ofSize: fontSize, weight: .ultraLight)
        #endif
        let ctFont = font as CTFont
        let text = NSAttributedString(string: "H O R I Z O N", attributes: [.font: font, .kern: 1.5])
        let line = CTLineCreateWithAttributedString(text)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let lineWidth = max(0.65, fontSize * 0.017)
        let sources: [CGRect] = [
            CGRect(x: 1, y: 1, width: 60, height: 71),
            CGRect(x: 112, y: 1, width: 60, height: 71),
            CGRect(x: 224, y: 1, width: 59, height: 71),
            CGRect(x: 358, y: 1, width: 0, height: 71),
            CGRect(x: 433, y: 1, width: 60, height: 71),
            CGRect(x: 543, y: 1, width: 60, height: 71),
            CGRect(x: 643, y: 1, width: 60, height: 71)
        ]
        let transforms = Array("HORIZON".utf16).enumerated().map { index, code in
            var character = code
            var glyph: CGGlyph = 0
            CTFontGetGlyphsForCharacters(ctFont, &character, &glyph, 1)
            let ink = CTFontGetBoundingRectsForGlyphs(ctFont, .horizontal, &glyph, nil, 1)
            let origin = CTLineGetOffsetForStringIndex(line, index * 2, nil)
            let target = CGRect(x: origin + ink.minX, y: font.capHeight - ink.maxY,
                                width: ink.width, height: ink.height)
                .insetBy(dx: min(lineWidth, ink.width) / 2, dy: min(lineWidth, ink.height) / 2)
            let source = sources[index]
            let sx = source.width == 0 ? 1 : target.width / source.width
            let sy = target.height / source.height
            return CGAffineTransform(a: sx, b: 0, c: 0, d: sy,
                tx: (source.width == 0 ? target.midX : target.minX) - source.minX * sx,
                ty: target.minY - source.minY * sy)
        }
        return LetterLayout(width: width, height: font.capHeight, lineWidth: lineWidth, transforms: transforms)
    }

    // Own centerline artwork, in a 704 × 73 coordinate space. No font outlines
    // or outside asset are used. Letter gaps echo the spaced welcome wordmark.
    private static let strokes: [Stroke] = {
        var result: [Stroke] = []
        var cursor: TimeInterval = 0
        var letter = 0
        // Each letter has an independent pen clock; the entire word starts
        // within 0.33 seconds, while strokes inside each letter remain ordered.
        func beginLetter(_ index: Int) {
            letter = index
            cursor = Double(index) * 0.055
        }
        func add(_ duration: TimeInterval = 0.27, _ draw: (inout Path) -> Void) {
            var path = Path()
            draw(&path)
            let drawingDuration = duration * 1.6
            result.append(Stroke(path: path, letter: letter, start: cursor, duration: drawingDuration))
            cursor += drawingDuration + 0.045
        }
        func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
            add { $0.move(to: CGPoint(x: x1, y: y1)); $0.addLine(to: CGPoint(x: x2, y: y2)) }
        }
        func oval(_ x: CGFloat) {
            add(0.46) { path in
                path.move(to: CGPoint(x: x + 31, y: 1))
                path.addCurve(to: CGPoint(x: x + 1, y: 36.5), control1: CGPoint(x: x + 10, y: 1), control2: CGPoint(x: x + 1, y: 13))
                path.addCurve(to: CGPoint(x: x + 31, y: 72), control1: CGPoint(x: x + 1, y: 60), control2: CGPoint(x: x + 10, y: 72))
                path.addCurve(to: CGPoint(x: x + 61, y: 36.5), control1: CGPoint(x: x + 52, y: 72), control2: CGPoint(x: x + 61, y: 60))
                path.addCurve(to: CGPoint(x: x + 31, y: 1), control1: CGPoint(x: x + 61, y: 13), control2: CGPoint(x: x + 52, y: 1))
            }
        }
        // H: stems, then crossbar.
        beginLetter(0)
        line(1, 1, 1, 72); line(61, 1, 61, 72); line(1, 36.5, 61, 36.5)
        beginLetter(1)
        oval(111)
        beginLetter(2)
        // R: stem, bowl, diagonal leg.
        line(224, 72, 224, 1)
        add(0.34) { path in
            path.move(to: CGPoint(x: 224, y: 1)); path.addLine(to: CGPoint(x: 252, y: 1))
            path.addCurve(to: CGPoint(x: 252, y: 37), control1: CGPoint(x: 288, y: 1), control2: CGPoint(x: 288, y: 37))
            path.addLine(to: CGPoint(x: 224, y: 37))
        }
        line(252, 37, 283, 72)
        beginLetter(3)
        line(358, 1, 358, 72) // I
        beginLetter(4)
        // Z: a continuous pen stroke across its two corners.
        add(0.42) { path in
            path.move(to: CGPoint(x: 433, y: 1)); path.addLine(to: CGPoint(x: 493, y: 1))
            path.addLine(to: CGPoint(x: 433, y: 72)); path.addLine(to: CGPoint(x: 493, y: 72))
        }
        beginLetter(5)
        oval(542)
        beginLetter(6)
        line(643, 72, 643, 1); line(643, 1, 703, 72); line(703, 72, 703, 1) // N
        return result
    }()
}
