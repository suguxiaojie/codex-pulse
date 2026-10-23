import Foundation

@main
enum SettingsSummaryTextTests {
    static func main() {
        let preview = SettingsSummaryText.countPreview
        precondition(preview(184_000_000, 5_410_000, .chinese) == "今日 1.84亿 · 30日 541万")
        precondition(preview(184_000_000, 5_410_000, .western) == "今日 184M · 30日 5.4M")
        precondition(preview(0, 0, .chinese) == "今日 0 · 30日 0")
        precondition(preview(nil, nil, .chinese) == "示例 1.84亿 · 541万")
        precondition(preview(nil, 1, .western) == "示例 184M · 5.4M")
        precondition(preview(1, nil, .chinese) == "示例 1.84亿 · 541万")
        precondition(preview(-1, 0, .chinese) == "示例 1.84亿 · 541万")
        precondition(preview(0, -1, .chinese) == "示例 1.84亿 · 541万")
        precondition(!preview(Int64.max, Int64.max, .western).contains("—"))
        let notifications = SettingsSummaryText.notifications
        precondition(notifications(true, true) == "信号与额度提醒已开启")
        precondition(notifications(false, false) == "信号与额度提醒已关闭")
        precondition(notifications(true, false) == "仅开启信号提醒")
        precondition(notifications(false, true) == "仅开启额度提醒")
        print("Settings summary tests: 13/13 passed")
    }
}
