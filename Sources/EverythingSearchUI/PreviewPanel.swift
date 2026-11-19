import AppKit
import SwiftUI
import Quartz
import AVKit
import UniformTypeIdentifiers
import EverythingCore

struct PreviewHoverPolicy {
    private var entered = false
    private var leftAt: TimeInterval?
    mutating func show() { entered = false; leftAt = nil }
    mutating func shouldHide(inside: Bool, inOvershoot: Bool, held: Bool, now: TimeInterval) -> Bool {
        if inside { entered = true }
        guard entered, !inside, !inOvershoot, !held else { leftAt = nil; return false }
        if leftAt == nil { leftAt = now }
        return now - (leftAt ?? now) >= 0.15
    }
}
struct PreviewEdgeHint: Equatable {
    let y: CGFloat
    let opacity: Double

    init?(point: CGPoint, in frame: CGRect) {
        let distance = frame.maxX - point.x
        guard distance >= 0, distance < 150, point.y >= frame.minY, point.y <= frame.maxY, frame.height >= 48 else { return nil }
        y = min(frame.height - 24, max(24, point.y - frame.minY))
        opacity = pow(1 - distance / 150, 2)
    }
}
@MainActor package final class PreviewController: ObservableObject {
    @Published private(set) var visible: Bool
    @Published var pinned: Bool { didSet { defaults.set(pinned, forKey: "Preview.pinned") } }
    @Published var favoritesExpanded: Bool { didSet { defaults.set(favoritesExpanded, forKey: "Preview.favoritesExpanded") } }
    @Published var preferredWidth: Double
    var isResizing = false
    private let defaults: UserDefaults
    func width(available: Double) -> Double { PreviewSizing.width(preferred: preferredWidth, available: available) }
    func saveWidth() { defaults.set(preferredWidth, forKey: "Preview.preferredWidth") }
    @Published private(set) var edgeHint: PreviewEdgeHint?
    var resultsFrame = CGRect.zero
    package weak var window: NSWindow?
    private var policy = PreviewHoverPolicy()
    private var suppressEdgeHint = false
    private var monitor: Task<Void, Never>?
    private var menuDepth = 0
    private var observers: [NSObjectProtocol] = []
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        visible = defaults.bool(forKey: "Preview.visible")
        pinned = defaults.bool(forKey: "Preview.pinned")
        favoritesExpanded = defaults.object(forKey: "Preview.favoritesExpanded") as? Bool ?? true
        let stored = defaults.object(forKey: "Preview.preferredWidth") as? Double ?? 360
        preferredWidth = stored.isFinite ? max(240, min(720, stored)) : 360
        for (name, delta) in [(NSMenu.didBeginTrackingNotification, 1), (NSMenu.didEndTrackingNotification, -1)] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { guard let self else { return }; self.menuDepth = max(0, self.menuDepth + delta) }
            })
        }
    }
    package func toggle() { visible ? hide() : show() }
    func show() {
        defaults.set(true, forKey: "Preview.visible")
        policy.show()
        edgeHint = nil
        visible = true
    }
    func hide(remember: Bool = true) {
        if remember { defaults.set(false, forKey: "Preview.visible") }
        suppressEdgeHint = true
        visible = false
    }
    func startMonitoring() {
        guard monitor == nil else { return }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                self?.updatePointer()
                do { try await Task.sleep(for: .milliseconds(50)) } catch { break }
            }
        }
    }
    func stopMonitoring() { monitor?.cancel(); monitor = nil }
    private func updatePointer() {
        guard let window, window.isVisible, window.isKeyWindow, let content = window.contentView else { return }
        let frame = resultsFrame
        let location = content.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let point = CGPoint(x: location.x - content.bounds.minX,
                            y: content.isFlipped ? location.y - content.bounds.minY : content.bounds.maxY - location.y)
        let width = width(available: frame.width)
        let withinHeight = point.y >= frame.minY && point.y <= frame.maxY
        let inside = withinHeight && point.x >= frame.maxX - width - 16 && point.x <= frame.maxX
        let overshoot = withinHeight && point.x > frame.maxX && point.x <= frame.maxX + 200
        let pressed = NSEvent.pressedMouseButtons != 0
        if !visible && !pressed {
            let hint = PreviewEdgeHint(point: point, in: frame)
            if hint == nil { suppressEdgeHint = false }
            let next = suppressEdgeHint ? nil : hint
            if edgeHint != next { edgeHint = next }
        }
        let editing = window.firstResponder is NSTextView
        if visible && !pinned && policy.shouldHide(inside: inside, inOvershoot: overshoot, held: isResizing || pressed || menuDepth > 0 || editing, now: Date.timeIntervalSinceReferenceDate) { hide(remember: false) }
    }
    isolated deinit {
        monitor?.cancel()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}
struct LocalQuickLook: NSViewRepresentable {
    let url: URL
    static func makePreviewView() -> QuickLookHostView { QuickLookHostView() }
    func makeNSView(context: Context) -> QuickLookHostView { Self.makePreviewView() }
    func updateNSView(_ view: QuickLookHostView, context: Context) { view.setItem(url) }
    static func dismantleNSView(_ view: QuickLookHostView, coordinator: ()) { view.finish() }
}
struct FilePreviewPanel: View {
    private struct Request: Equatable {
        let path: String?
        let mappings: [PathMapping]
    }
    private enum Content {
        case file(URL)
        case unavailable(String)
    }

    let result: SearchResult?
    let mappings: [PathMapping]
    @State private var loaded: (request: Request, content: Content)?

    var body: some View {
        let request = Request(path: result?.id, mappings: mappings)
        VStack(spacing: 0) {
            Text("Превью").font(.callout.weight(.medium)).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 12)
            if let result {
                Text(result.name).font(.headline).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 12)
                let content = loaded?.request == request ? loaded?.content : nil
                switch content {
                case .file(let url):
                    Group {
                        if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .movie) || type.conforms(to: .audio) {
                            MediaPreview(url: url)
                        } else { LocalQuickLook(url: url) }
                    }.id(url).frame(maxWidth: .infinity, maxHeight: .infinity)
                case .unavailable(let message):
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Превью недоступно").font(.callout.weight(.semibold))
                        Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                    Spacer()
                case nil:
                    Spacer()
                    ProgressView().controlSize(.small).accessibilityLabel("Загрузка превью")
                    Spacer()
                }
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Путь Windows").font(.caption).foregroundStyle(.secondary)
                    Text(result.windowsPath).font(.system(.caption, design: .monospaced))
                        .lineLimit(2).truncationMode(.middle).help(result.windowsPath).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 12)
            } else {
                Text("Выберите строку в результатах").font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                Spacer()
            }
        }
        .task(id: request) {
            loaded = nil
            guard let result else { return }
            do {
                let urls = try await FileAccess.resolve([result], mappings: mappings)
                try Task.checkCancellation()
                let content = urls.first.map(Content.file) ?? .unavailable("Не удалось открыть выбранный объект.")
                loaded = (request, content)
            } catch is CancellationError { }
            catch {
                if !Task.isCancelled { loaded = (request, .unavailable(error.localizedDescription)) }
            }
        }
    }
}

struct PreviewResizeHandle: View {
    @ObservedObject var controller: PreviewController
    let availableWidth: Double
    @State private var startingWidth: Double?
    var body: some View {
        Rectangle().fill(.white.opacity(controller.isResizing || controller.pinned ? 0.12 : 0))
            .frame(width: 1)
            .frame(width: 8, alignment: .leading)
            .padding(.vertical, controller.pinned ? 0 : 12)
            .contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() } }
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if startingWidth == nil { startingWidth = controller.width(available: availableWidth) }
                    controller.isResizing = true
                    controller.preferredWidth = PreviewSizing.width(preferred: (startingWidth ?? 360) - value.translation.width, available: availableWidth)
                }
                .onEnded { _ in
                    startingWidth = nil; controller.isResizing = false; controller.saveWidth()
                })
            .onDisappear { controller.isResizing = false }
            .help("Потяните, чтобы изменить ширину превью")
            .accessibilityLabel("Ширина панели превью")
            .accessibilityValue("\(Int(controller.width(available: availableWidth))) пт")
            .accessibilityAdjustableAction { direction in
                let width = controller.width(available: availableWidth)
                switch direction {
                case .increment: controller.preferredWidth = PreviewSizing.width(preferred: width + 32, available: availableWidth)
                case .decrement: controller.preferredWidth = PreviewSizing.width(preferred: width - 32, available: availableWidth)
                @unknown default: return
                }
                controller.saveWidth()
            }
    }
}

/// AVKit supplies native playback, seeking and volume controls; playback starts paused.
struct MediaPreview: NSViewRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        view.showsSharingServiceButton = false
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) {
        guard context.coordinator.url != url else { return }
        view.player?.pause()
        context.coordinator.url = url
        view.player = AVPlayer(playerItem: AVPlayerItem(asset: AVURLAsset(url: url)))
    }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        view.player?.pause()
        view.player?.replaceCurrentItem(with: nil)
        view.player = nil
    }
    @MainActor final class Coordinator { var url: URL? }
}
