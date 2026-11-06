#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import Librelog

/// The macOS editor swaps in its own NSTextView, which once kept its initial
/// 14pt frame: typing worked but nothing was ever drawn.
@MainActor
final class EditorRenderTests: XCTestCase {
    func testTypedTextDraws() throws {
        let controller = EditorController()
        let host = NSHostingView(rootView: ScrollView {
            RichTextEditor(controller: controller).frame(minHeight: 320)
        })
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                           styleMask: [.titled], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.contentView = host
        controller.load([])
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        let tv = try XCTUnwrap(textView(in: host))
        XCTAssertGreaterThanOrEqual(tv.frame.height, 320, "text view should fill the editor box")
        tv.insertText("Hello there this is typed text", replacementRange: tv.selectedRange())
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        var ink = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.brightnessComponent > 0.6 { ink += 1 }
            }
        }
        XCTAssertGreaterThan(ink, 50, "typed text should be drawn")
    }

    private func textView(in view: NSView) -> NSTextView? {
        if let t = view as? NSTextView { return t }
        return view.subviews.lazy.compactMap(textView(in:)).first
    }
}
#endif
