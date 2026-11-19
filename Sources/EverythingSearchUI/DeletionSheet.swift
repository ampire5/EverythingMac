import SwiftUI

struct DeletionSheet: View {
    let request: DeletionConfirmation
    let cancel: () -> Void
    let confirm: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Удалить безвозвратно?", systemImage: "exclamationmark.triangle")
                    .font(.title2.weight(.medium)).accessibilityAddTraits(.isHeader)
                Text("Объекты будут удалены с сетевого диска без помещения в Корзину.")
                    .foregroundStyle(.secondary)
                if request.targets.contains(where: { $0.result.type == "folder" }) {
                    Text("Папки будут удалены со всем содержимым.").foregroundStyle(.secondary)
                }
            }
            Divider()
            Text("Выбрано объектов: \(request.targets.count.formatted())")
                .font(.callout.weight(.medium)).monospacedDigit()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(request.targets) { target in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(target.result.name, systemImage: target.result.type == "folder" ? "folder" : "doc")
                            Text(target.url.path).font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 64, maxHeight: 240)
            HStack(spacing: 8) {
                Spacer()
                Button("Отмена", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                Button("Удалить безвозвратно", role: .destructive, action: confirm)
            }
        }.padding(24).frame(width: 560)
    }
}
