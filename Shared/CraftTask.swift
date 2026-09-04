import Foundation

nonisolated struct CraftTask: Identifiable, Sendable, Hashable {
    let id: String
    var text: String
    var isDone: Bool
    var scheduled: Date?
    var deadline: Date?
    var container: String?

    /// The date Craft itself sorts by: schedule if present, otherwise deadline.
    var taskDate: Date? { scheduled ?? deadline }

    var isOverdue: Bool {
        guard let taskDate, !isDone else { return false }
        return taskDate < Calendar.current.startOfDay(for: Date())
    }
}

/// Parses the plain-text listing that `craft_read tasks list` returns.
///
/// `tasks list` ignores `--format json`, so text is the only contract available. Lines
/// look like:
///
///     [ ] <uuid> - [ ] Buy milk
///       (schedule: 2026-08-31)
///       in: Home To Do List <uuid>
nonisolated enum TaskListParser {

    static func parse(_ output: String) -> [CraftTask] {
        // Built per call: Regex and DateFormatter are not Sendable, so they cannot be
        // stored as shared statics under strict concurrency.
        let header = /\[(.)\] <([^>]+)> - (.*)/
        let checkboxPrefix = /\[.\]\s*/
        let dateField = /\((schedule|deadline):\s*([0-9]{4}-[0-9]{2}-[0-9]{2})\)/
        let container = /in:\s*(.+)/
        let trailingID = /\s*<[^>]+>$/

        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"

        var tasks: [CraftTask] = []

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if let match = line.wholeMatch(of: header) {
                var text = String(match.3)
                if let prefix = text.prefixMatch(of: checkboxPrefix) {
                    text.removeSubrange(prefix.range)
                }
                tasks.append(
                    CraftTask(
                        id: String(match.2),
                        text: text.trimmingCharacters(in: .whitespaces),
                        isDone: match.1 != " ",
                        scheduled: nil,
                        deadline: nil,
                        container: nil
                    )
                )
                continue
            }

            // Continuation lines describe the task opened above them.
            guard !tasks.isEmpty else { continue }
            let index = tasks.count - 1

            if let match = line.wholeMatch(of: dateField) {
                let date = dayFormatter.date(from: String(match.2))
                if match.1 == "schedule" {
                    tasks[index].scheduled = date
                } else {
                    tasks[index].deadline = date
                }
            } else if let match = line.wholeMatch(of: container) {
                var name = String(match.1)
                if let idRange = name.firstMatch(of: trailingID)?.range {
                    name.removeSubrange(idRange)
                }
                tasks[index].container = name.trimmingCharacters(in: .whitespaces)
            }
        }

        return tasks
    }
}
