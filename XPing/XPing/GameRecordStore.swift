import Combine
import SwiftUI

/// 单局游戏记录，保存双方分数与结束时间。
struct GameRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let playerScore: Int
    let aiScore: Int
    let playedAt: Date

    /// 创建一条新的游戏记录。
    init(id: UUID = UUID(), playerScore: Int, aiScore: Int, playedAt: Date = Date()) {
        self.id = id
        self.playerScore = playerScore
        self.aiScore = aiScore
        self.playedAt = playedAt
    }

    /// 返回适合页面展示的比分文本。
    var scoreText: String {
        "\(playerScore) - \(aiScore)"
    }

    /// 返回本局比赛结果文本。
    var resultText: String {
        if playerScore == aiScore {
            return "Draw"
        }
        return playerScore > aiScore ? "Win" : "Loss"
    }

    /// 返回格式化后的记录时间。
    var playedAtText: String {
        Self.dateFormatter.string(from: playedAt)
    }

    /// 复用日期格式化器，减少列表刷新时的额外开销。
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

/// 游戏记录仓库，负责本地读写和删除记录。
final class GameRecordStore: ObservableObject {
    @Published private(set) var records: [GameRecord]

    private let storageKey = "LitePongGameRecords"
    private let maxRecordCount = 50

    /// 初始化并从本地存储加载已有记录。
    init() {
        records = []
        loadRecords()
    }

    /// 添加一条有效比分记录，并限制本地保存数量。
    func addRecord(playerScore: Int, aiScore: Int) {
        guard playerScore + aiScore > 0 else { return }

        let record = GameRecord(playerScore: playerScore, aiScore: aiScore)
        records.insert(record, at: 0)

        if records.count > maxRecordCount {
            records = Array(records.prefix(maxRecordCount))
        }

        saveRecords()
    }

    /// 按列表偏移删除记录。
    func deleteRecords(at offsets: IndexSet) {
        records.remove(atOffsets: offsets)
        saveRecords()
    }

    /// 删除指定的一条记录。
    func deleteRecord(_ record: GameRecord) {
        records.removeAll { $0.id == record.id }
        saveRecords()
    }

    /// 清空所有游戏记录。
    func deleteAllRecords() {
        records.removeAll()
        saveRecords()
    }

    /// 从本地存储读取历史记录。
    private func loadRecords() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }

        do {
            records = try JSONDecoder().decode([GameRecord].self, from: data)
        } catch {
            records = []
        }
    }

    /// 将当前记录写入本地存储。
    private func saveRecords() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

/// 游戏记录页面，展示历史比分并提供删除操作。
struct GameRecordsView: View {
    @ObservedObject var recordStore: GameRecordStore
    @Environment(\.dismiss) private var dismiss
    @State private var showsClearConfirmation = false

    /// 构建带导航栏的游戏记录列表页面。
    var body: some View {
        NavigationView {
            Group {
                if recordStore.records.isEmpty {
                    emptyState
                } else {
                    recordList
                }
            }
            .navigationTitle("Game Records")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") {
                        showsClearConfirmation = true
                    }
                    .disabled(recordStore.records.isEmpty)
                }
            }
            .alert("Clear Records?", isPresented: $showsClearConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    recordStore.deleteAllRecords()
                }
            } message: {
                Text("All game records will be deleted.")
            }
        }
    }

    /// 展示无记录时的空状态。
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("No Records Yet")
                .font(.title3.weight(.bold))

            Text("Finish a match to save your first record.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    /// 构建支持左滑删除的记录列表。
    private var recordList: some View {
        List {
            ForEach(recordStore.records) { record in
                GameRecordRow(record: record) {
                    recordStore.deleteRecord(record)
                }
            }
            .onDelete(perform: recordStore.deleteRecords)
        }
    }
}

/// 游戏记录单元格，展示结果、比分、时间和删除按钮。
private struct GameRecordRow: View {
    let record: GameRecord
    let deleteAction: () -> Void

    /// 构建单条游戏记录的展示内容。
    var body: some View {
        HStack(spacing: 14) {
            resultBadge

            VStack(alignment: .leading, spacing: 5) {
                Text(record.scoreText)
                    .font(.title3.weight(.black))

                Text(record.playedAtText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive, action: deleteAction) {
                Image(systemName: "trash")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
    }

    /// 构建展示胜负结果的徽章。
    private var resultBadge: some View {
        Text(record.resultText)
            .font(.caption.weight(.black))
            .foregroundStyle(.white)
            .frame(width: 52, height: 32)
            .background(badgeColor, in: Capsule())
    }

    /// 根据比赛结果返回徽章颜色。
    private var badgeColor: Color {
        if record.playerScore == record.aiScore {
            return .gray
        }
        return record.playerScore > record.aiScore ? .green : .red
    }
}
