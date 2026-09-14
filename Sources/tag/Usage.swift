import Foundation

struct UsageCounter {
    private var counts: [String: Int] = [:]
    private var names: [String: String] = [:]
    private var order: [String] = []

    mutating func add(_ tags: [String]) {
        for tag in tags {
            let key = canonicalTag(tag)
            if counts[key] == nil {
                counts[key] = 0
                names[key] = tag
                order.append(key)
            }
            counts[key] = (counts[key] ?? 0) + 1
        }
    }

    func entries(reverse: Bool) -> [UsageEntry] {
        let keys = reverse ? Array(order.reversed()) : order
        return keys.map { key in
            UsageEntry(tag: names[key] ?? key, count: counts[key] ?? 0)
        }
    }
}
