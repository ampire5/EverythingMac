import EverythingSearchUI
import SwiftUI
import AppKit
import EverythingCore

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @State private var draft: Configuration
    @State private var password: String
    @State private var error: String?
    @State private var saved = false
    @State private var shares: [MountedShare] = []
    @AppStorage(SearchActivationController.preferenceKey) private var focusAfterClipboardChange = false
    @AppStorage(MenuBarPreferences.closeToMenuBar) private var closeToMenuBar = false
    @AppStorage(MenuBarPreferences.doubleClickAction) private var menuBarDoubleClick = "tab"
    init(store: SettingsStore) {
        self.store = store
        _draft = State(initialValue: store.config)
        _password = State(initialValue: store.password)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Окна и поиск").font(.headline)
                Toggle("Скрывать последнее окно в строку меню", isOn: $closeToMenuBar)
                Picker("Двойной щелчок по значку в строке меню", selection: $menuBarDoubleClick) {
                    Text("Новая вкладка").tag("tab")
                    Text("Новое окно").tag("window")
                }.fixedSize()
                Toggle("Активировать поиск, если при возврате изменился буфер обмена", isOn: $focusAfterClipboardChange)
                Text("При возврате в приложение прежний запрос выделяется для вставки через ⌘V")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Подключение к Everything").font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Сервер")
                        TextField("Сервер", text: $draft.server, prompt: Text("http://server.local:1980")).labelsHidden()
                    }
                    GridRow {
                        Text("Логин")
                        TextField("Логин", text: $draft.login, prompt: Text(verbatim: "")).labelsHidden()
                    }
                    GridRow {
                        Text("Пароль")
                        SecureField("Пароль", text: $password, prompt: Text(verbatim: "")).labelsHidden()
                    }
                }
                .textFieldStyle(.roundedBorder)
                Text("Пароль Everything хранится в Связке ключей. Подключением SMB управляет Finder.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Сетевые папки").font(.headline)
                    Spacer()
                    Menu("Из подключённых") {
                        if shares.isEmpty { Text("Нет подключённых SMB-папок") }
                        ForEach(shares) { share in
                            Button(share.mountPath) {
                                if !draft.mappings.contains(where: { MountedShare.sameShare($0.shareURL, share.shareURL) }) {
                                    draft.mappings.append(PathMapping(windowsRoot: share.driveRoot ?? "\\\\server\\Share", shareURL: share.shareURL, mountPath: share.mountPath))
                                }
                            }
                        }
                    }
                    Button {
                        Task { await refreshShares() }
                    } label: { Image(systemName: "arrow.clockwise") }
                        .help("Обновить подключённые папки").accessibilityLabel("Обновить подключённые папки")
                    Button {
                        draft.mappings.append(PathMapping(windowsRoot: "", shareURL: "smb://", mountPath: "/Volumes/"))
                    } label: { Image(systemName: "plus") }
                        .help("Добавить правило").accessibilityLabel("Добавить правило")
                }
                Text("Три пути в правиле указывают на одну папку. При совпадении используется самое точное правило.")
                    .font(.callout).foregroundStyle(.secondary)
                if draft.mappings.isEmpty {
                    Text("Выберите подключённую папку или добавьте правило вручную")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(12)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach($draft.mappings) { $mapping in
                                mappingEditor($mapping)
                            }
                        }.padding(.trailing, 8)
                    }
                }
            }
            Divider()
            HStack(spacing: 12) {
                if let error { Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled) }
                else if saved && draft == store.config && password == store.password {
                    Label("Сохранено", systemImage: "checkmark").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Сохранить") {
                    do {
                        draft.server = draft.server.trimmingCharacters(in: .whitespacesAndNewlines)
                        try store.save(draft, password: password)
                        error = nil; saved = true
                        NotificationCenter.default.post(name: .reloadConnection, object: nil)
                    } catch { self.error = error.localizedDescription; saved = false }
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 680, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await refreshShares() }
    }
    private func mappingEditor(_ mapping: Binding<PathMapping>) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Windows").foregroundStyle(.secondary)
                TextField("Путь Windows", text: mapping.windowsRoot, prompt: Text("C:\\Media"))
                    .labelsHidden()
                Button(role: .destructive) {
                    let id = mapping.wrappedValue.id
                    draft.mappings.removeAll { $0.id == id }
                } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .help("Удалить правило").accessibilityLabel("Удалить правило")
                    .gridColumnAlignment(.trailing)
            }
            GridRow {
                Text("SMB").foregroundStyle(.secondary)
                TextField("Адрес SMB", text: mapping.shareURL, prompt: Text("smb://server/Media"))
                    .labelsHidden()
            }
            GridRow {
                Text("Mac").foregroundStyle(.secondary)
                TextField("Путь на Mac", text: mapping.mountPath, prompt: Text("/Volumes/Media"))
                    .labelsHidden()
                Button("Выбрать…") { selectFolder(for: mapping.wrappedValue.id) }
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(12)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }
    private func refreshShares() async {
        shares = await Task.detached { MountedShare.snapshot() }.value
    }
    private func selectFolder(for id: UUID) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "Выберите подключённую SMB-папку. Адрес ресурса обновится автоматически."
        panel.begin { response in
            guard response == .OK, let url = panel.url, let index = draft.mappings.firstIndex(where: { $0.id == id }) else { return }
            let currentShares = MountedShare.snapshot()
            shares = currentShares
            guard let share = currentShares.sorted(by: { $0.mountPath.count > $1.mountPath.count }).first(where: { url.path == $0.mountPath || url.path.hasPrefix($0.mountPath + "/") }), var remote = URL(string: share.shareURL) else {
                error = "Выберите папку внутри подключённого SMB-ресурса."
                return
            }
            let relative = String(url.path.dropFirst(share.mountPath.count)).split(separator: "/")
            for component in relative { remote.appendPathComponent(String(component), isDirectory: true) }
            draft.mappings[index].mountPath = url.path
            draft.mappings[index].shareURL = remote.absoluteString
        }
    }
}
