import SwiftUI
import AppKit

struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    let windowID: UUID
    var onCommit: () -> Void = {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Поиск файлов и папок"
        field.setAccessibilityLabel("Поиск Everything")
        field.controlSize = .large
        field.font = .systemFont(ofSize: 15)
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchAction(_:))
        field.stringValue = text
        context.coordinator.field = field
        let contextID = windowID
        context.coordinator.observer = NotificationCenter.default.addObserver(forName: .focusSearch, object: nil, queue: .main) { [weak field, weak coordinator = context.coordinator] notification in
            // The observer explicitly delivers on the main queue.
            let targetID = notification.object as? UUID
            MainActor.assumeIsolated {
                guard let field, let coordinator, targetID == contextID else { return }
                // A Service can change the binding before SwiftUI renders the field.
                if field.stringValue != coordinator.parent.text { field.stringValue = coordinator.parent.text }
                field.window?.makeFirstResponder(field)
                field.selectText(nil)
            }
        }
        return field
    }
    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }
    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NativeSearchField
        weak var field: NSSearchField?
        var observer: NSObjectProtocol?
        init(_ parent: NativeSearchField) { self.parent = parent }
        isolated deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
        func controlTextDidChange(_ obj: Notification) { updateQuery() }
        func controlTextDidEndEditing(_ obj: Notification) { parent.onCommit() }
        @objc func searchAction(_ sender: NSSearchField) { updateQuery() }
        private func updateQuery() {
            if let field, parent.text != field.stringValue { parent.text = field.stringValue }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.moveDown(_:)) || commandSelector == #selector(NSResponder.insertNewline(_:)) {
                NotificationCenter.default.post(name: .focusResults, object: parent.windowID)
                return true
            }
            return false
        }
    }
}
