import Foundation

/// 本地「規劃日」。以年月日識別，不用「加 24 小時」推算日期（夏令時間、跨時區安全）。
public struct LocalDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// 解析 "yyyy-MM-dd"
    public init?(_ string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    /// 當地這一天的開始（遇到午夜不存在的夏令時間，Foundation 會取當天第一個有效時刻）
    public func start(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    /// 當日某分鐘（自 00:00 起算）對應的時刻
    public func instant(minute: Int, in calendar: Calendar) -> Date {
        let base = start(in: calendar)
        return calendar.date(byAdding: .minute, value: minute, to: base) ?? base
    }

    public func adding(days: Int, calendar: Calendar) -> LocalDay {
        let s = start(in: calendar)
        let shifted = calendar.date(byAdding: .day, value: days, to: s) ?? s
        return LocalDay(shifted, calendar: calendar)
    }

    /// 星期幾：1 = 週日 … 7 = 週六（同 Calendar.weekday）
    public func weekday(in calendar: Calendar) -> Int {
        calendar.component(.weekday, from: start(in: calendar))
    }

    public static func < (a: LocalDay, b: LocalDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    public static func today(_ now: Date = Date(), calendar: Calendar = .current) -> LocalDay {
        LocalDay(now, calendar: calendar)
    }
}

public func formatMinute(_ minute: Int) -> String {
    let m = ((minute % 1440) + 1440) % 1440
    return String(format: "%02d:%02d", m / 60, m % 60)
}

public func formatDuration(_ minutes: Int) -> String {
    if minutes < 60 { return "\(minutes) 分" }
    let h = minutes / 60, m = minutes % 60
    return m == 0 ? "\(h) 小時" : "\(h) 小時 \(m) 分"
}
