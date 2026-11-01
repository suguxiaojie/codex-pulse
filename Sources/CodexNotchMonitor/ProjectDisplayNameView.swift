import SwiftUI

struct ProjectDisplayNameView: View {
    @ObservedObject var store: MonitorStore
    let draft: ProjectDisplayNameDraft
    @State private var name: String

    init(store: MonitorStore, draft: ProjectDisplayNameDraft) {
        self.store = store
        self.draft = draft
        _name = State(initialValue: draft.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("历史分组显示名称").font(.headline)
            Text("此目录没有对应的 Codex 项目登记。名称仅用于 Pulse 显示，不会新建项目、移动文件或改变会话归属。")
                .fixedSize(horizontal: false, vertical: true)
            TextField("显示名称", text: $name).textFieldStyle(.roundedBorder)
                .disabled(store.isProjectRenaming)
            Text(draft.id).font(.system(.caption, design: .monospaced))
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if let error = store.projectRenameError { Text(error).foregroundStyle(.red) }
            HStack {
                if store.isProjectRenaming { ProgressView().controlSize(.small) }
                Spacer()
                Button("取消") { store.projectDisplayNameDraft = nil }
                    .keyboardShortcut(.cancelAction).disabled(store.isProjectRenaming)
                Button("保存显示名称") { store.saveProjectDisplayName(draft, name: name) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(store.isProjectRenaming || (try? ProjectRenameEngine.validatedName(name)) == nil)
            }
        }
        .padding(24).frame(width: 460)
        .interactiveDismissDisabled(store.isProjectRenaming)
    }
}
