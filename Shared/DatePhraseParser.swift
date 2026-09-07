import Foundation

/// A date (and possibly a time) found inside dictated text.
nonisolated struct DatePhrase: Sendable, Equatable {
    /// The resolved instant. Only the day is meaningful unless `hasTime` is true.
    var date: Date
    /// True only when the speaker actually named a clock time. A bare day such as
    /// "tomorrow" resolves to 12:00, which must not be mistaken for noon.
    var hasTime: Bool
    /// The words that produced the date, e.g. "tomorrow at three o'clock".
    var phrase: String
    /// What remains of the text once the date phrase is removed and tidied.
    var title: String
    /// True when the utterance was nothing but a date, so `title` is the original words.
    /// Callers should not append a time label in that case — it is already in the text.
    var usedFallbackTitle: Bool
}

/// Pulls a due date out of natural speech: "set appointment for tomorrow at three
/// o'clock" becomes a task titled "Set appointment", scheduled tomorrow, carrying 3:00 PM.
///
/// `NSDataDetector` does the language work — it is on-device, needs no network, and
/// already understands spelled-out times, weekday names and relative days.
nonisolated enum DatePhraseParser {

    /// Openers that describe the act of capturing rather than the task itself.
    private static let leadingFiller = [
        "i need to", "i have to", "i want to", "i should",
        "remind me to", "remind me", "don't forget to", "dont forget to",
        "make sure to", "make sure i", "note to self", "please",
    ]

    static func parse(_ text: String, relativeTo now: Date = Date()) -> DatePhrase? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.date.rawValue
        ) else { return nil }

        let ns = trimmed as NSString
        let matches = detector.matches(in: trimmed, range: NSRange(location: 0, length: ns.length))

        // Prefer the longest match: "tomorrow at three o'clock" carries more than "tomorrow".
        guard let match = matches.max(by: { $0.range.length < $1.range.length }),
              let date = match.date
        else { return nil }

        let phrase = ns.substring(with: match.range)

        // Checked against the matched *words*, not the resolved time: the detector
        // answers 12:00 for a bare day, so the clock value cannot tell "tomorrow" from
        // "noon". Vague parts of the day ("Saturday afternoon" → 15:00) are excluded on
        // purpose — recording 3:00 PM would invent precision the speaker never gave.
        // Built here rather than stored: Regex is not Sendable.
        // "at 3" and "at three" count too: a bare hour is common in dictation, and the
        // detector has already decided this whole span is a date expression, so a number
        // following "at" inside it is a time rather than a quantity.
        let timeIndicator = /(\d{1,2}:\d{2})|(\b\d{1,2}\s*[ap]\.?\s?m\.?\b)|(o'?\s?clock)|(\bnoon\b)|(\bmidday\b)|(\bmidnight\b)|(\bat\s+\d{1,2}\b)|(\bat\s+(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b)/
            .ignoresCase()
        let hasTime = phrase.contains(timeIndicator)

        var remainder = ns.replacingCharacters(in: match.range, with: " ")
        remainder = cleanTitle(remainder)

        // If the sentence was nothing but a date, keep the original words rather than
        // leaving the task blank.
        let usedFallback = remainder.isEmpty

        return DatePhrase(
            date: date,
            hasTime: hasTime,
            phrase: phrase,
            title: usedFallback ? trimmed : remainder,
            usedFallbackTitle: usedFallback
        )
    }

    private static func cleanTitle(_ raw: String) -> String {
        var value = raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        value = value.trimmingCharacters(in: .whitespaces)

        // Strip capture-intent openers, longest first so "i need to" wins over "i".
        let lowered = value.lowercased()
        for filler in leadingFiller.sorted(by: { $0.count > $1.count }) {
            if lowered.hasPrefix(filler) {
                value = String(value.dropFirst(filler.count))
                break
            }
        }

        // Trailing words left dangling once the date phrase is cut out of the middle of
        // a sentence: "set appointment for" → "set appointment". Repeated, since
        // "call Ryan on at" can leave two.
        let danglingTail =
            /[\s,;:–—-]+(for|on|at|by|due|to|in|from|until|till|starting|beginning)\s*$/
                .ignoresCase()
        while let tail = value.firstMatch(of: danglingTail) {
            value.removeSubrange(tail.range)
        }

        value = value.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:.-–—"))
        guard let first = value.first else { return "" }
        return first.uppercased() + value.dropFirst()
    }

    /// `YYYY-MM-DD` in the user's own calendar, which is what Craft's `--schedule` wants.
    static func craftDay(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Locale-formatted clock time, appended to the task text since Craft tasks store
    /// only a date.
    static func timeLabel(for date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// The task text to send to Craft for a parsed phrase: the tidied title, plus the
    /// clock time when one was actually spoken and is not already in the title.
    static func taskText(for phrase: DatePhrase) -> String {
        guard phrase.hasTime, !phrase.usedFallbackTitle else { return phrase.title }
        return "\(phrase.title) — \(timeLabel(for: phrase.date))"
    }
}
