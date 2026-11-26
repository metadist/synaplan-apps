import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The Synaplan bird as the state picture of the CarPlay voice screen.
///
/// CarPlay plays a looping frame sequence (cycle between 0.3 and 5 seconds, at
/// most 150 by 150 points), so every phase is drawn frame by frame from the
/// bird outline: no bitmaps ship with the app. The drawing is plain Core
/// Graphics, so the frames can be rendered and inspected on a Mac as well.
enum CarPlayBirdArtwork {
    enum Motion: CaseIterable {
        case connecting
        case listening
        case thinking
        case speaking
        case muted
    }

    struct Palette {
        let bird: CGColor
        let accent: CGColor

        static let dark = Palette(
            bird: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            accent: CGColor(red: 0.50, green: 0.55, blue: 1, alpha: 1)
        )
        static let light = Palette(
            bird: CGColor(red: 0, green: 0.012, blue: 0.78, alpha: 1),
            accent: CGColor(red: 0.30, green: 0.36, blue: 1, alpha: 1)
        )
    }

    /// Edge of the square canvas in points, the largest CarPlay accepts.
    static let side: CGFloat = 150
    /// One loop. Every motion closes on itself within this time.
    static let cycle: TimeInterval = 1.6
    static let frameCount = 20

    private static let birdSize = CGSize(width: 211.2, height: 256.38)
    private static let birdHeight: CGFloat = 64

    /// Draws one frame into a context whose origin is the top-left corner.
    /// `progress` runs from 0 up to, but not including, 1.
    static func draw(_ motion: Motion, progress: CGFloat, palette: Palette, in context: CGContext) {
        let center = side / 2
        switch motion {
        case .connecting:
            let start = progress * 2 * .pi
            context.saveGState()
            context.setStrokeColor(palette.accent)
            context.setLineWidth(2.5)
            context.setLineCap(.round)
            context.addArc(
                center: CGPoint(x: center, y: center),
                radius: 52,
                startAngle: start,
                endAngle: start + 0.9,
                clockwise: false
            )
            context.strokePath()
            context.restoreGState()
            drawBird(in: context, color: palette.bird, alpha: 0.55 + 0.45 * wave(progress))

        case .listening:
            for ring in 0..<2 {
                let phase = (progress + CGFloat(ring) / 2).truncatingRemainder(dividingBy: 1)
                let radius = 31 + 38 * phase
                context.saveGState()
                context.setAlpha(0.75 * (1 - phase))
                context.setStrokeColor(palette.accent)
                context.setLineWidth(1.5)
                context.strokeEllipse(in: CGRect(
                    x: center - radius,
                    y: center - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                context.restoreGState()
            }
            drawBird(in: context, color: palette.bird, scale: 1 + 0.07 * wave(progress))

        case .thinking:
            let count = 12
            for index in 0..<count {
                var phase = (progress - CGFloat(index) / CGFloat(count)).truncatingRemainder(dividingBy: 1)
                if phase < 0 { phase += 1 }
                let glow = max(0, 1 - phase / 0.6)
                drawSpoke(
                    in: context,
                    color: palette.accent,
                    angle: CGFloat(index) / CGFloat(count) * 2 * .pi,
                    length: 9 * (1 + 0.35 * glow),
                    alpha: 0.18 + 0.82 * glow
                )
            }
            drawBird(in: context, color: palette.bird, rotation: -0.12 * cos(progress * 2 * .pi))

        case .speaking:
            let count = 20
            for index in 0..<count {
                let offset = CGFloat((index * 7) % count) / CGFloat(count)
                drawSpoke(
                    in: context,
                    color: palette.accent,
                    angle: CGFloat(index) / CGFloat(count) * 2 * .pi,
                    length: 7 * (0.35 + 1.15 * wave(progress * 2 + offset)),
                    alpha: 1
                )
            }
            drawBird(in: context, color: palette.bird, lift: 2.5 * wave(progress * 2))

        case .muted:
            drawBird(in: context, color: palette.bird, alpha: 0.4)
        }
    }

    /// 0 at whole numbers, 1 halfway between them.
    private static func wave(_ value: CGFloat) -> CGFloat {
        0.5 - 0.5 * cos(value * 2 * .pi)
    }

    private static func drawSpoke(in context: CGContext, color: CGColor, angle: CGFloat, length: CGFloat, alpha: CGFloat) {
        let width: CGFloat = 3.5
        let innerRadius: CGFloat = 49
        context.saveGState()
        context.translateBy(x: side / 2, y: side / 2)
        context.rotate(by: angle)
        context.setAlpha(alpha)
        context.setFillColor(color)
        let rect = CGRect(x: -width / 2, y: -(innerRadius + length), width: width, height: length)
        let radius = min(width, length) / 2
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
        context.restoreGState()
    }

    private static func drawBird(
        in context: CGContext,
        color: CGColor,
        alpha: CGFloat = 1,
        scale: CGFloat = 1,
        rotation: CGFloat = 0,
        lift: CGFloat = 0
    ) {
        let fit = birdHeight / birdSize.height * scale
        context.saveGState()
        context.translateBy(x: side / 2, y: side / 2 - lift)
        context.rotate(by: rotation)
        context.scaleBy(x: fit, y: fit)
        context.translateBy(x: -birdSize.width / 2, y: -birdSize.height / 2)
        context.setAlpha(alpha)
        context.setFillColor(color)
        context.addPath(birdPath)
        context.fillPath()
        context.restoreGState()
    }

    // MARK: - Bird outline

    private static let birdPath: CGPath = parse(birdOutline)

    /// Reads the relative `m`, `l`, `c` and `z` commands the outline uses.
    private static func parse(_ data: String) -> CGPath {
        let path = CGMutablePath()
        var tokens: [String] = []
        var number = ""
        func flush() {
            if !number.isEmpty { tokens.append(number) }
            number = ""
        }
        for character in data {
            if character.isLetter {
                flush()
                tokens.append(String(character))
            } else if character == "," || character == " " {
                flush()
            } else if character == "-" {
                flush()
                number = "-"
            } else {
                number.append(character)
            }
        }
        flush()

        var current = CGPoint.zero
        var start = CGPoint.zero
        var command = ""
        var index = 0
        func next() -> CGFloat {
            defer { index += 1 }
            return index < tokens.count ? CGFloat(Double(tokens[index]) ?? 0) : 0
        }
        while index < tokens.count {
            if tokens[index].first?.isLetter == true {
                command = tokens[index]
                index += 1
                if command == "z" {
                    path.closeSubpath()
                    current = start
                }
                continue
            }
            switch command {
            case "m":
                current = CGPoint(x: current.x + next(), y: current.y + next())
                start = current
                path.move(to: current)
                command = "l"
            case "l":
                current = CGPoint(x: current.x + next(), y: current.y + next())
                path.addLine(to: current)
            case "c":
                let first = CGPoint(x: current.x + next(), y: current.y + next())
                let second = CGPoint(x: current.x + next(), y: current.y + next())
                let end = CGPoint(x: current.x + next(), y: current.y + next())
                path.addCurve(to: end, control1: first, control2: second)
                current = end
            default:
                index += 1
            }
        }
        return path
    }

    /// The path of `single_bird.svg` (view box 211.2 by 256.38).
    private static let birdOutline = "m67.06,158.58l19.18,0c-0.29,6.75 -1.53,13.38 -3.17,19.9c5.85,-0.06 11.88,0.2 17.71,-0.61c5.83,-0.81 13.87,-5.74 11.88,-14.39c-1.12,-4.84 -4.18,-6.46 -8.33,-8.39c-13.5,-6.32 -27.91,-10.81 -41.44,-17.1c-4.38,-1.33 -9.08,0.95 -12.4,3.75c-15.4,12.98 -17.97,47.99 -19.32,66.9c0,0.32 -0.09,1.3 0.14,1.3c19.18,-10.73 32.93,-29.47 35.33,-51.62c0.12,-0.14 0.35,0.29 0.43,0.29l0,-0.03l-0.01,0zm65.03,95.16c0.37,-9.52 -5.59,-16.96 -14.27,-20.19c-7.64,-2.85 -16.55,-0.66 -24.54,-1.61c-7.81,8.97 -17.53,16.24 -29.13,19.47c-9.34,2.6 -18.74,2.45 -28.38,2.34c-0.14,-0.66 0.09,-0.46 0.37,-0.63c2.97,-1.9 7.24,-3.55 10.5,-5.36c14.94,-8.39 27.48,-19.52 37.58,-33.36l15.46,-0.12c29.88,-0.61 60.7,-22.55 58.68,-54.96c-1.93,-31.06 -36.91,-37.86 -59.61,-49.11c-6.66,-3.32 -13.84,-7.53 -17.45,-14.27c-7.44,-13.93 2.16,-29.44 17.48,-30.48c5.31,-0.37 13.47,-0.35 18.77,0c6.2,0.4 13.7,3.11 15.92,9.46c5.08,14.45 -16.03,19 -17.27,4.15c-5.83,-0.32 -17.01,-0.49 -15.8,8.16c1.21,8.65 6.23,7.24 9.49,8.97c8.33,4.44 17.85,7.56 26.44,11.62c3.75,1.79 7.44,3.75 11.04,5.83c1.21,-7.27 0.81,-14.65 0.87,-22c11.53,-7.27 12.63,-22.38 3.75,-32.36c-12.86,-14.53 -37,-14.68 -54.96,-13.7c-27.48,1.5 -50.58,23.73 -42.3,52.43c8.07,28.03 42.36,30.8 64.11,42.88c24.4,13.58 17.13,45.45 -8.22,52.63c-10.7,3.03 -22.03,1.1 -33.02,1.87c-16.88,28.46 -45.92,47.78 -77.58,56.35c-0.2,-0.2 1.61,-2.71 1.87,-3.17c10.04,-18.14 9.8,-38.32 11.97,-58.4c2.77,-25.78 7.38,-54.33 30.86,-69.5c-6.23,-6.75 -9.98,-15.75 -11.19,-24.83c-1.36,-10.04 -0.26,-20.47 3.72,-29.79c-14.04,-1.27 -23.62,-14.65 -25.95,-27.68c12.86,4.18 26.33,6.14 39.8,7.21l-9.8,-4.47c-8.02,-4.47 -13.84,-10.93 -16.49,-19.84c-2.08,-6.95 -2.25,-14.07 -1.64,-21.28c11.56,10.7 25.84,19.7 41.18,23.85c27.94,7.56 56.81,-2.19 83.89,9.83c16.73,7.44 33.8,24.48 29.07,44.47c18.6,6.63 28.89,27.86 20.76,46.4c-3.43,7.84 -10.35,14.71 -18.6,17.3c2.57,-6.08 3.37,-18.83 -4.24,-21.57c-0.37,-0.14 -2.05,-0.63 -2.25,-0.63l-13.7,0c1.59,3.52 4.44,6 6.75,8.97c23.65,30.39 8.42,71.57 -21.6,90.81c-2.51,1.61 -5.25,2.94 -7.64,4.61c1.04,0.92 1.79,0.4 3,0.61c12.34,2.13 22.44,11.04 24.08,23.79c0.2,1.67 0.23,3.6 0.32,5.31l-32.07,0l-0.03,-0.01l0,0z"
}

#if canImport(UIKit)
extension CarPlayBirdArtwork {
    @MainActor private static var cache: [String: UIImage] = [:]

    /// The looping picture for one voice state, drawn for the car screen's
    /// light or dark appearance. Rendered once per appearance and kept.
    @MainActor
    static func image(for state: VoiceState, traits: UITraitCollection) -> UIImage? {
        let isLight = traits.userInterfaceStyle == .light
        let key = "\(state.rawValue)-\(isLight ? "light" : "dark")"
        if let cached = cache[key] { return cached }

        let motion: Motion
        switch state {
        case .connecting: motion = .connecting
        case .listening: motion = .listening
        case .thinking: motion = .thinking
        case .speaking: motion = .speaking
        case .muted: motion = .muted
        }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        // Twice the point size is sharp enough for a head unit and keeps the
        // frame sequences small.
        format.scale = min(max(traits.displayScale, 1), 2)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let palette: Palette = isLight ? .light : .dark
        // A still picture needs two frames to count as an animation.
        let count = motion == .muted ? 2 : frameCount
        let frames = (0..<count).map { frame in
            renderer.image { context in
                draw(motion, progress: CGFloat(frame) / CGFloat(count), palette: palette, in: context.cgContext)
            }
        }
        let image = UIImage.animatedImage(with: frames, duration: cycle)
        cache[key] = image
        return image
    }
}
#endif
