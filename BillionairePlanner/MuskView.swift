import SwiftUI
import SwiftData

/// 馬斯克時間顆粒：大腦傾倒 → 拖進 06:00–24:00 網格（15 分 / 5 分極限）。
struct MuskView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TimeBlock.startMinute) private var allBlocks: [TimeBlock]
    @Query(sort: \BrainDumpItem.createdAt) private var dump: [BrainDumpItem]
    @Query(sort: \RichGoal.createdAt) private var goals: [RichGoal]
    @Query(sort: \PrincipleLog.createdAt, order: .reverse) private var principles: [PrincipleLog]

    @AppStorage("granularity") private var gran = 15
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var newTask = ""
    @State private var newTag = ContextTag.deep.rawValue
    @State private var newGoal = ""          // "" = 不連結
    @State private var principleHint: PrincipleLog?
    @State private var buzz = 0

    // ponytail: 全部讀出再依日期過濾，資料量到數萬筆再改成動態 Predicate
    private var blocks: [TimeBlock] { allBlocks.filter { $0.day == day } }
    private var activeGoals: [RichGoal] { goals.filter(\.isActive) }
    private var slots: [Int] { Array(stride(from: 6 * 60, to: 24 * 60, by: gran)) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                dumpPanel
                if let hint = batchingHint { banner(hint, color: .yellow) }
                if let p = principleHint {
                    banner("📜 \(p.tag) 原則：\(p.concretePrinciple)", color: .assetGreen) { principleHint = nil }
                }
                grid
            }
            .background(Color.black)
            .navigationTitle("馬斯克時間顆粒")
            .sensoryFeedback(.error, trigger: buzz)
            .onChange(of: day) { _, d in
                let s = Calendar.current.startOfDay(for: d)
                if s != d { day = s }
            }
            .onChange(of: allBlocks.map { "\($0.id)\($0.day)\($0.startMinute)\($0.isDone)" }) {
                Notifier.sync(context)
            }
        }
    }

    // MARK: 頂部：日期與顆粒度

    private var header: some View {
        let total = blocks.reduce(0) { $0 + $1.durationMinutes }
        let doneCount = blocks.filter(\.isDone).count
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                DatePicker("", selection: $day, displayedComponents: .date).labelsHidden()
                Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
                Spacer()
                Picker("顆粒度", selection: $gran) {
                    Text("15 分").tag(15)
                    Text("5 分極限").tag(5)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }
            Text("已排 \(total / 60) 小時 \(total % 60) 分 · 完成 \(doneCount)/\(blocks.count)")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal).padding(.top, 8)
    }

    // MARK: 大腦傾倒區

    private var dumpPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("大腦傾倒：今日高槓桿任務", text: $newTask)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addDump)
                Picker("標籤", selection: $newTag) {
                    ForEach(ContextTag.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .labelsHidden().fixedSize()
                Button(action: addDump) { Image(systemName: "plus.circle.fill").font(.title2) }
                    .buttonStyle(.borderless)
                    .disabled(newTask.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Picker("對應目標", selection: $newGoal) {
                Text("不連結目標").tag("")
                ForEach(activeGoals) { Text("🎯 \($0.title)").tag($0.title) }
            }
            .pickerStyle(.menu)
            .font(.caption)

            if dump.isEmpty {
                Text("只有 Top 5 目標能被排程。新增任務後，拖到下方網格或點空格放入。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(dump) { chip($0) } }.padding(.vertical, 2)
                }
            }
        }
        .padding()
    }

    private func chip(_ item: BrainDumpItem) -> some View {
        let c = ContextTag.color(item.tag)
        return Text(item.title)
            .font(.subheadline.bold())
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(c.opacity(0.2), in: Capsule())
            .overlay(Capsule().stroke(c))
            .draggable("dump:\(item.id.uuidString)")
            .contextMenu { Button("刪除", role: .destructive) { context.delete(item) } }
    }

    // MARK: 網格

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(slots, id: \.self) { m in slotRow(m).id(m) }
                }
                .padding(.horizontal).padding(.bottom)
            }
            .onAppear {
                let now = Calendar.current.dateComponents([.hour, .minute], from: .now)
                let m = (now.hour ?? 0) * 60 + (now.minute ?? 0)
                if day == Calendar.current.startOfDay(for: .now), m >= 6 * 60 {
                    proxy.scrollTo(m - m % gran, anchor: .top)
                }
            }
        }
    }

    private func slotRow(_ m: Int) -> some View {
        let block = blocks.first { $0.startMinute < m + gran && $0.endMinute > m }
        return HStack(spacing: 8) {
            Text(hhmm(m))
                .font(.caption.monospacedDigit())
                .foregroundStyle(m % 60 == 0 ? Color.white : .secondary)
                .frame(width: 44, alignment: .trailing)
            if let b = block {
                blockCell(b, isHead: b.startMinute >= m)
            } else {
                emptyCell(m)
            }
        }
        .frame(height: gran == 5 ? 22 : 34)
        .dropDestination(for: String.self) { items, _ in
            guard let s = items.first else { return false }
            return handleDrop(s, at: m)
        }
    }

    private func blockCell(_ b: TimeBlock, isHead: Bool) -> some View {
        let c = ContextTag.color(b.tag)
        return HStack(spacing: 6) {
            if isHead {
                Image(systemName: b.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(c)
                    .onTapGesture { b.isDone.toggle() }
                Text(b.taskTitle).font(.subheadline.bold()).strikethrough(b.isDone).lineLimit(1)
                if let g = b.goalTitle {
                    Text("🎯\(g)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text("\(b.durationMinutes)m").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                Text(b.tag)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(c.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(c)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(c.opacity(isHead ? 0.22 : 0.12), in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) { Rectangle().fill(c).frame(width: 3) }
        .draggable("block:\(b.id.uuidString)")
        .contextMenu {
            Button("延長 \(gran) 分") { resize(b, by: gran) }
            Button("縮短 \(gran) 分") { resize(b, by: -gran) }.disabled(b.durationMinutes <= gran)
            Button(b.isDone ? "標為未完成" : "標為完成") { b.isDone.toggle() }
            Button("退回大腦傾倒區") { unschedule(b) }
            Button("刪除", role: .destructive) { context.delete(b) }
        }
    }

    private func emptyCell(_ m: Int) -> some View {
        Menu {
            if dump.isEmpty { Text("大腦傾倒區是空的") }
            ForEach(dump) { item in
                Button("\(item.title)  \(item.tag)") { place(item, at: m) }
            }
        } label: {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.guardGray.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3]))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    private func banner(_ text: String, color: Color, dismiss: (() -> Void)? = nil) -> some View {
        HStack(alignment: .top) {
            Text(text).font(.caption).foregroundStyle(color)
            Spacer()
            if let dismiss {
                Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.borderless).font(.caption)
            }
        }
        .padding(10)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal).padding(.bottom, 6)
    }

    /// 同一標籤被切成多段時提醒黏合（降低大腦切換成本）
    private var batchingHint: String? {
        var segments: [String: Int] = [:]
        var last: String?
        for b in blocks.sorted(by: { $0.startMinute < $1.startMinute }) where b.tag != last {
            segments[b.tag, default: 0] += 1
            last = b.tag
        }
        guard let worst = segments.filter({ $0.value > 1 }).max(by: { $0.value < $1.value }) else { return nil }
        return "🧠 \(worst.key) 被切成 \(worst.value) 段，試著把同標籤黏在一起，減少大腦切換成本。"
    }

    // MARK: 動作

    private func shiftDay(_ n: Int) {
        day = Calendar.current.date(byAdding: .day, value: n, to: day) ?? day
    }

    private func isFree(_ start: Int, _ duration: Int, ignoring: TimeBlock? = nil) -> Bool {
        start >= 0 && start + duration <= 24 * 60 &&
            !blocks.contains { $0.id != ignoring?.id && $0.startMinute < start + duration && $0.endMinute > start }
    }

    private func addDump() {
        let t = newTask.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        context.insert(BrainDumpItem(title: t, tag: newTag, goalTitle: newGoal.isEmpty ? nil : newGoal))
        newTask = ""
    }

    @discardableResult
    private func place(_ item: BrainDumpItem, at m: Int) -> Bool {
        guard isFree(m, gran) else { buzz += 1; return false }
        let b = TimeBlock(taskTitle: item.title, tag: item.tag, goalTitle: item.goalTitle,
                          day: day, startMinute: m, durationMinutes: gran)
        context.insert(b)
        context.delete(item)
        principleHint = principles.first { $0.tag == b.tag }
        return true
    }

    private func handleDrop(_ payload: String, at m: Int) -> Bool {
        if let item = dump.first(where: { "dump:\($0.id.uuidString)" == payload }) {
            return place(item, at: m)
        }
        if let b = allBlocks.first(where: { "block:\($0.id.uuidString)" == payload }) {
            guard isFree(m, b.durationMinutes, ignoring: b) else { buzz += 1; return false }
            b.day = day
            b.startMinute = m
            return true
        }
        return false
    }

    private func resize(_ b: TimeBlock, by delta: Int) {
        let d = b.durationMinutes + delta
        guard d >= 5, isFree(b.startMinute, d, ignoring: b) else { buzz += 1; return }
        b.durationMinutes = d
    }

    private func unschedule(_ b: TimeBlock) {
        context.insert(BrainDumpItem(title: b.taskTitle, tag: b.tag, goalTitle: b.goalTitle))
        context.delete(b)
    }
}
