import Foundation

struct UsageCounter {
    private var counts: [String: Int] = [:]
    private var order: [String] = []

    mutating func add(_ tags: [String]) {
        // Case is part of the stored tag. Matching can be case-insensitive,
        // but usage must not merge "orange" and "Orange" into one bucket.
        for tag in tags {
            if counts[tag] == nil {
                counts[tag] = 0
                order.append(tag)
            }
            counts[tag] = (counts[tag] ?? 0) + 1
        }
    }

    func entries(reverse: Bool) -> [UsageEntry] {
        let tags = reverse ? Array(order.reversed()) : order
        return tags.map { UsageEntry(tag: $0, count: counts[$0] ?? 0) }
    }
}
