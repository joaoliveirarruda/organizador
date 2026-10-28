import CoreGraphics
import SwiftUI

enum Palette {
    static let colors = [
        "#FF6B6B", "#F7B731", "#20BF6B", "#2D98DA",
        "#8854D0", "#FA8231", "#0FB9B1", "#EB3B5A",
    ]
}

extension Color {
    /// Accepts "#RRGGBB". Falls back to gray for anything else.
    init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self = .gray
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

enum IdleMonitor {
    /// Seconds since the last keyboard, mouse or trackpad input anywhere on the Mac.
    static func secondsSinceLastInput() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }
}
