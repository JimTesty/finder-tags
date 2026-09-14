import Foundation

func foldedTag(_ tag: String) -> String {
    return tag.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
}

func tagsEqual(_ lhs: String, _ rhs: String, caseSensitive: Bool) -> Bool {
    return caseSensitive ? lhs == rhs : foldedTag(lhs) == foldedTag(rhs)
}

func sortedTagArray(_ tags: [String]) -> [String] {
    // NSString/String compare: is the closest straightforward analogue to
    // jdberry/tag's sortedArrayUsingSelector:@selector(compare:). Include the
    // original index as a tiebreaker so equal strings remain stable.
    return tags.enumerated().sorted { lhs, rhs in
        let result = lhs.element.compare(rhs.element)
        if result == .orderedSame { return lhs.offset < rhs.offset }
        return result == .orderedAscending
    }.map { $0.element }
}

func sortedChangeIfRequested(_ change: TagChange, options: Options) -> TagChange {
    if !options.sortedTags { return change }
    return TagChange(before: change.before, after: sortedTagArray(change.after))
}

func parsePosition(_ raw: String) -> PositionSpec {
    switch raw.lowercased() {
    case "first", "left", "bottom":
        return .first
    case "last", "right", "top":
        return .last
    default:
        guard let value = Int(raw), value >= 0 else {
            fail("invalid position '\(raw)'; use a zero-based index or first/left/bottom/last/right/top")
        }
        return .index(value)
    }
}

private func validateTagName(_ tag: String) {
    // NSURLTagNamesKey does not round-trip line breaks reliably on macOS: a
    // write can succeed but a subsequent read returns only the prefix before
    // the newline. Reject values we know cannot be represented faithfully.
    if tag.contains("\n") || tag.contains("\r") || tag.unicodeScalars.contains("\0") {
        fail("tag names may not contain CR, LF, or NUL characters")
    }
}

// Parse a small CSV-like tag grammar. Shell quotes around the whole argument
// are removed by the shell; quotes *inside* the argument allow literal commas:
//   'Red,"Project, Alpha",Blue'
// Both single and double quotes are accepted. A doubled quote inside a quoted
// tag represents one literal quote, CSV-style.
func parseTagList(_ raw: String) -> [String] {
    if raw.isEmpty { return [] }

    let chars = Array(raw)
    var result: [String] = []
    var exactSeen = Set<String>()
    var i = 0

    func appendTag(_ value: String, quoted: Bool) {
        let tag = quoted ? value : value.trimmingCharacters(in: .whitespacesAndNewlines)
        if tag.isEmpty { return }
        validateTagName(tag)
        // Preserve case-only variants. Only exact duplicates are redundant.
        if exactSeen.insert(tag).inserted { result.append(tag) }
    }

    while i < chars.count {
        while i < chars.count && chars[i].isWhitespace { i += 1 }

        var value = ""
        var quoted = false

        if i < chars.count && (chars[i] == "\"" || chars[i] == "'") {
            quoted = true
            let quote = chars[i]
            i += 1
            var closed = false

            while i < chars.count {
                let ch = chars[i]
                if ch == quote {
                    if i + 1 < chars.count && chars[i + 1] == quote {
                        value.append(quote)
                        i += 2
                    } else {
                        i += 1
                        closed = true
                        break
                    }
                } else {
                    value.append(ch)
                    i += 1
                }
            }

            if !closed { fail("unterminated quoted tag in TAGS") }
            while i < chars.count && chars[i].isWhitespace { i += 1 }
            if i < chars.count && chars[i] != "," {
                fail("unexpected text after quoted tag; separate tags with commas")
            }
        } else {
            while i < chars.count && chars[i] != "," {
                value.append(chars[i])
                i += 1
            }
        }

        appendTag(value, quoted: quoted)
        if i < chars.count {
            if chars[i] != "," { fail("invalid TAGS syntax") }
            i += 1
        }
    }

    return result
}

func validateSingleTagOperand(_ tag: String) {
    if tag.isEmpty { fail("tag name must not be empty") }
    validateTagName(tag)
}

func tagsMatch(_ stored: [String], query: [String], caseSensitive: Bool) -> Bool {
    if query.contains("*") { return !stored.isEmpty }
    if query.isEmpty { return stored.isEmpty }

    for wanted in query {
        if !stored.contains(where: { tagsEqual($0, wanted, caseSensitive: caseSensitive) }) {
            return false
        }
    }
    return true
}
