import SwiftUI
import WidgetKit

/// The complication is the app's front door: it shows what is left today and taps
/// straight into dictation. It reads a cached count from the shared app group rather
/// than authenticating, so it never blocks on the network.
struct OpenTasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenTasks", provider: OpenTasksProvider()) { entry in
            OpenTasksView(entry: entry)
                .widgetURL(URL(string: "craftwatch://capture"))
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Craft Tasks")
        .description("Open tasks due today. Tap to dictate a new one.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular,
        ])
    }
}

struct OpenTasksEntry: TimelineEntry {
    let date: Date
    let count: Int?
    let pending: Int

    static let placeholder = OpenTasksEntry(date: .now, count: 3, pending: 0)
}

struct OpenTasksProvider: TimelineProvider {
    func placeholder(in context: Context) -> OpenTasksEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (OpenTasksEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OpenTasksEntry>) -> Void) {
        // The app reloads timelines whenever the count actually changes; this refresh is
        // only a backstop so a stale count cannot linger all day.
        let next = Date(timeIntervalSinceNow: 30 * 60)
        completion(Timeline(entries: [currentEntry()], policy: .after(next)))
    }

    private func currentEntry() -> OpenTasksEntry {
        OpenTasksEntry(date: .now, count: SharedDefaults.openTaskCount, pending: SharedDefaults.pendingCount)
    }
}

struct OpenTasksView: View {
    @Environment(\.widgetFamily) private var family
    let entry: OpenTasksEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(inlineText, systemImage: "checklist")

        case .accessoryCorner:
            Text(countText)
                .font(.title2)
                .widgetCurvesContent()
                .widgetLabel(entry.pending > 0 ? "\(entry.pending) queued" : "Craft")

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("Craft", systemImage: "mic.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(countText + (entry.count == 1 ? " task" : " tasks"))
                    .font(.headline)
                if entry.pending > 0 {
                    Text("\(entry.pending) queued")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

        default:
            VStack(spacing: 0) {
                Image(systemName: "checklist")
                    .font(.caption2)
                Text(countText)
                    .font(.title3)
                    .fontWeight(.semibold)
            }
        }
    }

    private var countText: String {
        entry.count.map(String.init) ?? "–"
    }

    private var inlineText: String {
        guard let count = entry.count else { return "Craft" }
        return count == 0 ? "Craft · clear" : "Craft · \(count) due"
    }
}
