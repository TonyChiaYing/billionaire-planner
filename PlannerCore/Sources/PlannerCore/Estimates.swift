import Foundation

/// 可選估時＋本機歷史建議（PRD 7.4 / AC-07）。不足三筆相似紀錄時不給數字。
public struct EstimateSample: Sendable, Equatable {
    public var title: String
    public var goalID: UUID?
    public var context: ItemContext
    public var actualMinutes: Int
    public var completedAt: Date
    public var wasCancelled: Bool
    public var isInferred: Bool

    public init(title: String, goalID: UUID?, context: ItemContext, actualMinutes: Int, completedAt: Date,
                wasCancelled: Bool = false, isInferred: Bool = false) {
        self.title = title
        self.goalID = goalID
        self.context = context
        self.actualMinutes = actualMinutes
        self.completedAt = completedAt
        self.wasCancelled = wasCancelled
        self.isInferred = isInferred
    }
}

public struct EstimateSuggestion: Sendable, Equatable {
    public let minutes: Int
    public let sampleCount: Int
    public let lowMinutes: Int
    public let highMinutes: Int

    public var basis: String {
        "依據 \(sampleCount) 筆相似紀錄的中位數（範圍 \(lowMinutes)–\(highMinutes) 分）"
    }
}

public enum EstimateSuggester {
    public static let minimumSamples = 3
    public static let maxSamples = 20

    /// 使用者已填估時就不建議，永不覆寫。
    public static func suggest(title: String, goalID: UUID?, context: ItemContext, userEstimate: Int?,
                               history: [EstimateSample]) -> EstimateSuggestion? {
        guard userEstimate == nil else { return nil }
        let samples = comparable(title: title, goalID: goalID, context: context, history: history)
        guard samples.count >= minimumSamples else { return nil }
        let values = samples.map(\.actualMinutes).sorted()
        let mid = values.count / 2
        let median = values.count % 2 == 1 ? Double(values[mid]) : Double(values[mid - 1] + values[mid]) / 2
        let rounded = max(5, Int((median / 5).rounded()) * 5)
        return EstimateSuggestion(minutes: rounded, sampleCount: values.count,
                                  lowMinutes: values.first ?? rounded, highMinutes: values.last ?? rounded)
    }

    static func comparable(title: String, goalID: UUID?, context: ItemContext, history: [EstimateSample]) -> [EstimateSample] {
        let grams = bigrams(title)
        return history
            .filter { !$0.wasCancelled && !$0.isInferred && $0.actualMinutes > 0 }
            .filter { s in
                if let g = goalID, s.goalID == g { return true }
                guard s.context == context else { return false }
                return similarity(grams, bigrams(s.title)) >= 0.3
            }
            .sorted { $0.completedAt > $1.completedAt }
            .prefix(maxSamples)
            .map { $0 }
    }

    /// 字元二元組：中文沒有空白分詞，也能比較標題相似度
    static func bigrams(_ s: String) -> Set<String> {
        let chars = Array(s.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation })
        guard chars.count > 1 else { return chars.isEmpty ? [] : [String(chars)] }
        return Set((0..<(chars.count - 1)).map { String(chars[$0...$0 + 1]) })
    }

    static func similarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(a.union(b).count)
    }
}
