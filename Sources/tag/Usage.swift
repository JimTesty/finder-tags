import Foundation

struct UsageCounter {
    private var counts: [String: Int] = [:]
    private var order: [String] = []
    private var colors: [String: Set<Int>] = [:]
    private var unknownColors = Set<String>()

    mutating func add(_ tags: [StoredTag]) {
        // Case is part of the stored tag. Matching can be case-insensitive,
        // but usage must not merge "orange" and "Orange" into one bucket.
        for value in tags {
            let tag = value.name
            if counts[tag] == nil {
                counts[tag] = 0
                order.append(tag)
            }
            counts[tag] = (counts[tag] ?? 0) + 1
            if let color = value.color {
                colors[tag, default: []].insert(color)
            } else {
                unknownColors.insert(tag)
            }
        }
    }

    func entries(sorted: Bool, reverse: Bool) -> [UsageEntry] {
        var tags = sorted ? sortedTagArray(order) : order
        if reverse { tags.reverse() }
        return tags.map { UsageEntry(
            tag: $0, count: counts[$0] ?? 0, colors: colors[$0] ?? [],
            hasUnknownColor: unknownColors.contains($0)
        ) }
    }
}
