import Foundation

/// Where each part of the bar sits: an ordered row of sections with one
/// flexible space somewhere in it. Everything before the space hugs the
/// left end of the bar, everything after it hugs the right.
///
/// One list with a movable gap, rather than a side per section, because
/// that is how the bar actually reads — and it means a single drag both
/// reorders a section and moves it across.
struct BarLayout: Equatable {

    enum Section: String, CaseIterable {
        case dock, brightness, volume, mute

        var title: String {
            switch self {
            case .dock:       return "Dock"
            case .brightness: return "Brightness"
            case .volume:     return "Volume"
            case .mute:       return "Mute / Unmute"
            }
        }

        var symbolName: String {
            switch self {
            case .dock:       return "dock.rectangle"
            case .brightness: return "sun.max"
            case .volume:     return "speaker.wave.2.fill"
            case .mute:       return "speaker.slash"
            }
        }
    }

    /// One slot in the row. The space is the boundary between the sides.
    enum Slot: Equatable {
        case section(Section)
        case space

        fileprivate var storageKey: String {
            switch self {
            case .section(let section): return section.rawValue
            case .space:                return Self.spaceKey
            }
        }

        fileprivate static let spaceKey = "space"
    }

    /// Left to right. Always holds every section exactly once, plus one space.
    private(set) var slots: [Slot]

    /// Brightness at the left end, as F1 and F2 have it on a Mac keyboard
    /// without a Touch Bar; the Dock beside it; sound at the right.
    static let standard = BarLayout(slots: [
        .section(.brightness), .section(.dock), .space, .section(.volume), .section(.mute),
    ])

    var left: [Section] { sections(in: slots.prefix { $0 != .space }) }
    var right: [Section] { sections(in: slots.drop { $0 != .space }) }

    init(slots: [Slot]) {
        self.slots = Self.repaired(slots)
    }

    mutating func move(from source: Int, to destination: Int) {
        guard slots.indices.contains(source) else { return }
        var slots = self.slots
        let slot = slots.remove(at: source)
        slots.insert(slot, at: min(max(destination, 0), slots.count))
        self.slots = slots
    }

    private func sections<S: Sequence>(in slots: S) -> [Section] where S.Element == Slot {
        slots.compactMap { if case .section(let section) = $0 { return section } else { return nil } }
    }

    /// Whatever came out of storage, make it usable: drop unknowns and
    /// repeats, and put back anything missing. A section added in a later
    /// version lands at the right end, which is where controls have
    /// always lived.
    private static func repaired(_ slots: [Slot]) -> [Slot] {
        var seen: [Slot] = []
        for slot in slots where !seen.contains(slot) {
            seen.append(slot)
        }
        if !seen.contains(.space) {
            seen.append(.space)
        }
        for section in Section.allCases where !seen.contains(.section(section)) {
            seen.append(.section(section))
        }
        return seen
    }

    // MARK: - Persistence

    private static let defaultsKey = "barLayout"

    /// Posted on the main thread whenever `current` is set.
    static let didChange = Notification.Name("dev.ctoasap.touchmybar.barLayoutDidChange")

    static var current: BarLayout {
        get {
            guard let stored = UserDefaults.standard.stringArray(forKey: defaultsKey) else {
                return .standard
            }
            return BarLayout(slots: stored.compactMap { key in
                if key == Slot.spaceKey { return .space }
                return Section(rawValue: key).map { .section($0) }
            })
        }
        set {
            guard newValue != current else { return }
            UserDefaults.standard.set(newValue.slots.map(\.storageKey), forKey: defaultsKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }
}
