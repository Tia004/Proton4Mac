import AppKit
import CoreGraphics

enum DisplayPolicy {
    static var preferred: NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        } ?? NSScreen.screens.first { $0.localizedName.localizedCaseInsensitiveContains("retina") && !$0.localizedName.localizedCaseInsensitiveContains("samsung") }
    }

    static func constrain(_ rectangle: NSRect, to screen: NSScreen) -> NSRect {
        let bounds = screen.visibleFrame
        let size = NSSize(width: min(rectangle.width, bounds.width), height: min(rectangle.height, bounds.height))
        return NSRect(x: min(max(rectangle.minX, bounds.minX), bounds.maxX - size.width),
                      y: min(max(rectangle.minY, bounds.minY), bounds.maxY - size.height),
                      width: size.width, height: size.height)
    }

    static func place(_ window: NSWindow, centered: Bool = false) {
        guard let screen = preferred else { window.orderOut(nil); return }
        var frame = window.frame
        if centered {
            frame.origin = NSPoint(x: screen.visibleFrame.midX - frame.width / 2,
                                   y: screen.visibleFrame.midY - frame.height / 2)
        }
        let constrained = constrain(frame, to: screen)
        if window.frame != constrained { window.setFrame(constrained, display: true) }
    }

    static var inventory: [[String: Any]] {
        NSScreen.screens.map { screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return ["id": id, "name": screen.localizedName, "builtin": CGDisplayIsBuiltin(id) != 0,
                    "preferred": screen == preferred, "x": screen.frame.minX, "y": screen.frame.minY,
                    "width": screen.frame.width, "height": screen.frame.height]
        }
    }
}
