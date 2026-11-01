import SwiftUI

struct ProjectRenameView: View {
    @ObservedObject var store: MonitorStore
    let project: ProjectRenameRecord
    @State private var name: String

    init(store: MonitorStore, project: ProjectRenameRecord) {
        self.store = store
        self.project = project
        _name = State(initialValue: project.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("重命名 Codex 项目").font(.headline)
            Text("修改 Codex 中的项目名称，文件夹路径和会话归属保持不变。")
                .fixedSize(horizontal: false, vertical: true)
            TextField("项目名称", text: $name).textFieldStyle(.roundedBorder)
                .disabled(store.isProjectRenaming)
            ScrollView {
                Text(project.roots.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 70)
            if let error = store.projectRenameError { Text(error).foregroundStyle(.red) }
            HStack {
                if store.isProjectRenaming { ProgressView().controlSize(.small) }
                Spacer()
                Button("取消") { store.projectRenameDraft = nil }
                    .keyboardShortcut(.cancelAction).disabled(store.isProjectRenaming)
                Button("保存到 Codex") { store.renameProject(project, to: name) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(store.isProjectRenaming || (try? ProjectRenameEngine.validatedName(name)) == nil)
            }
        }
        .padding(24).frame(width: 460)
        .interactiveDismissDisabled(store.isProjectRenaming)
    }
}
