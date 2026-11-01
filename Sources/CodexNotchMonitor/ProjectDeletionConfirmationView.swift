import SwiftUI

struct ProjectDeletionConfirmationView: View {
    let draft: ProjectDeletionDraft
    let cancel: () -> Void
    let confirm: () -> Void
    @State private var folderName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("删除所选项目及其文件夹？")
                .font(.headline)
            Text("项目：\(draft.project.name) · \(draft.project.threads.count) 条会话")
            Text("以下文件夹及全部内容（包括子文件夹和隐藏文件）将移入废纸篓。会话会永久删除，无法撤销。")
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(draft.plan.directory.path)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(height: 90)
            Text("请输入文件夹名「\(draft.plan.directory.lastPathComponent)」确认目标：")
                .fixedSize(horizontal: false, vertical: true)
            TextField("文件夹名", text: $folderName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("删除会话并移入废纸篓", role: .destructive, action: confirm)
                    .disabled(folderName != draft.plan.directory.lastPathComponent)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
