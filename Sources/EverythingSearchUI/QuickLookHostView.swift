import AppKit
import Quartz

/// Own Quick Look's lifetime explicitly; SwiftUI receives an ordinary container view.
final class QuickLookHostView: NSView {
    private var preview: QLPreviewView?
    private var itemURL: URL?
    private var finished = false

    func setItem(_ url: URL) {
        guard !finished else { return }
        itemURL = url
        if let preview, (preview.previewItem as? NSURL) != url as NSURL {
            preview.previewItem = url as NSURL
        }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !finished, window != nil, preview == nil,
              let view = QLPreviewView(frame: bounds, style: .compact) else { return }
        // Never combine window-driven close with representable-driven close.
        view.shouldCloseWithWindow = false
        view.autostarts = false
        view.translatesAutoresizingMaskIntoConstraints = false
        preview = view
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        if let itemURL { view.previewItem = itemURL as NSURL }
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        // Close while still attached, before Quick Look can be detached/deactivated by AppKit.
        if newWindow !== window { releasePreview() }
        super.viewWillMove(toWindow: newWindow)
    }
    func finish() {
        guard !finished else { return }
        finished = true
        itemURL = nil
        releasePreview()
    }
    private func releasePreview() {
        guard let view = preview else { return }
        preview = nil // Clear ownership before potentially reentrant AppKit callbacks.
        view.close()
        view.removeFromSuperview()
    }
}
