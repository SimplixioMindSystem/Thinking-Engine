//
//  CortexWidget.swift
//  CortexOS Widget
//
//  Lock Screen + Home Screen widget showing your #1 priority.
//  Glanceable clarity — see what matters without opening the app.
//
//  Supported families:
//  - accessoryCircular    (Lock Screen — rank badge)
//  - accessoryRectangular (Lock Screen — priority + why)
//  - accessoryInline      (Lock Screen — single line)
//  - systemSmall          (Home Screen — top priority card)
//  - systemMedium         (Home Screen — top 3 priorities)
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct CortexEntry: TimelineEntry {
    let date: Date
    let data: CortexWidgetData
}

// MARK: - Timeline Provider

struct CortexTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> CortexEntry {
        CortexEntry(
            date: .now,
            data: CortexWidgetData(
                topPriority: WidgetPriority(
                    rank: 1,
                    title: "Ship the feature",
                    whyItMatters: "Users are waiting",
                    nextStep: "Write the tests"
                ),
                priorities: [],
                date: "Today",
                updatedAt: .now
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CortexEntry) -> Void) {
        let data = WidgetDataBridge.read()
        completion(CortexEntry(date: .now, data: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CortexEntry>) -> Void) {
        let data = WidgetDataBridge.read()
        let entry = CortexEntry(date: .now, data: data)

        // Refresh every 30 minutes — widget updates when app syncs anyway
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now)
            ?? Date().addingTimeInterval(30 * 60)
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }
}

// MARK: - Widget Configuration

struct CortexFocusWidget: Widget {
    let kind = "CortexFocusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CortexTimelineProvider()) { entry in
            CortexWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Focus")
        .description("Your #1 priority from SimpliXio.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .systemSmall,
            .systemMedium,
        ])
    }
}

// MARK: - Widget Entry View (routes to the right family)

struct CortexWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: CortexEntry

    private let focusURL = URL(string: "simplixio://focus")

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                CircularView(entry: entry)
            case .accessoryRectangular:
                RectangularView(entry: entry)
            case .accessoryInline:
                InlineView(entry: entry)
            case .systemSmall:
                SmallView(entry: entry)
            case .systemMedium:
                MediumView(entry: entry)
            default:
                SmallView(entry: entry)
            }
        }
        .widgetURL(focusURL)
    }
}

// MARK: - Lock Screen: Circular (priority badge)

private struct CircularView: View {
    let entry: CortexEntry

    var body: some View {
        if let top = entry.data.topPriority {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 2) {
                    Image(systemName: "target")
                        .font(.system(size: 14, weight: .bold))
                    Text(abbreviate(top.title))
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 2) {
                    Image(systemName: "target")
                        .font(.system(size: 16, weight: .light))
                    Text("—")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Abbreviate to first 2 meaningful words
    private func abbreviate(_ text: String) -> String {
        let skip: Set<String> = ["the", "a", "an", "to", "and", "or", "for", "in", "on", "at", "of"]
        let words = text.split(separator: " ").map(String.init)
        let meaningful = words.filter { !skip.contains($0.lowercased()) }
        return meaningful.prefix(2).joined(separator: " ")
    }
}

// MARK: - Lock Screen: Rectangular (priority + next step)

private struct RectangularView: View {
    let entry: CortexEntry

    var body: some View {
        if let top = entry.data.topPriority {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "target")
                        .font(.caption2)
                    Text("#1")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.secondary)

                Text(top.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                // Show next step (actionable) over why (passive)
                if !top.nextStep.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8, weight: .bold))
                        Text(top.nextStep)
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                } else if !top.whyItMatters.isEmpty {
                    Text(top.whyItMatters)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Label("SimpliXio", systemImage: "target")
                    .font(.caption2.weight(.semibold))
                Text("No focus set")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Lock Screen: Inline (single line — #1 priority)

private struct InlineView: View {
    let entry: CortexEntry

    var body: some View {
        if let top = entry.data.topPriority {
            Label {
                Text("#1: \(top.title)")
            } icon: {
                Image(systemName: "target")
            }
        } else {
            Label("No focus set", systemImage: "target")
        }
    }
}

// MARK: - Home Screen: Small (top priority card)

private struct SmallView: View {
    let entry: CortexEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "target")
                    .font(.caption2)
                    .foregroundStyle(.blue.opacity(0.8))
                Text("FOCUS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if let top = entry.data.topPriority {
                Text(top.title)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !top.whyItMatters.isEmpty {
                    Text(top.whyItMatters)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if !top.nextStep.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.blue.opacity(0.7))
                        Text(top.nextStep)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                Spacer()
                Text("Open SimpliXio to set your focus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Home Screen: Medium (top 3 priorities)

private struct MediumView: View {
    let entry: CortexEntry
    private let captureURL = URL(string: "simplixio://capture")

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "target")
                        .font(.caption2)
                        .foregroundStyle(.blue.opacity(0.8))
                    Text("TODAY'S FOCUS")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !entry.data.date.isEmpty {
                    Text(entry.data.date)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            let items = entry.data.priorities.isEmpty
                ? (entry.data.topPriority.map { [$0] } ?? [])
                : Array(entry.data.priorities.prefix(3))

            if items.isEmpty {
                Spacer()
                Text("Open SimpliXio to choose your focus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(items) { priority in
                    HStack(spacing: 8) {
                        Text("\(priority.rank)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(rankColor(priority.rank))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 1) {
                            Text(priority.title)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)

                            if !priority.nextStep.isEmpty {
                                Text(priority.nextStep)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                }

                HStack {
                    Spacer()
                    if let captureURL {
                        Link(destination: captureURL) {
                            Label("Capture", systemImage: "square.and.pencil")
                                .font(.caption2)
                                .foregroundStyle(.blue.opacity(0.8))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1:  return Color(red: 0.38, green: 0.42, blue: 1.0)
        case 2:  return Color(red: 0.45, green: 0.50, blue: 0.90)
        case 3:  return Color(red: 0.55, green: 0.58, blue: 0.78)
        default: return .gray
        }
    }
}

// MARK: - Widget Bundle

@main
struct CortexWidgetBundle: WidgetBundle {
    var body: some Widget {
        CortexFocusWidget()
    }
}

// MARK: - Previews

#if WIDGET_PREVIEWS
#Preview("Lock Screen Circular", as: .accessoryCircular) {
    CortexFocusWidget()
} timeline: {
    CortexEntry(
        date: .now,
        data: CortexWidgetData(
            topPriority: WidgetPriority(rank: 1, title: "Decide launch focus", whyItMatters: "Too many open loops", nextStep: "Pick one release priority"),
            priorities: [],
            date: "2026-04-09",
            updatedAt: .now
        )
    )
}

#Preview("Lock Screen Rectangular", as: .accessoryRectangular) {
    CortexFocusWidget()
} timeline: {
    CortexEntry(
        date: .now,
        data: CortexWidgetData(
            topPriority: WidgetPriority(rank: 1, title: "Decide launch focus", whyItMatters: "Too many open loops", nextStep: "Pick one release priority"),
            priorities: [],
            date: "2026-04-09",
            updatedAt: .now
        )
    )
}

#Preview("Home Small", as: .systemSmall) {
    CortexFocusWidget()
} timeline: {
    CortexEntry(
        date: .now,
        data: CortexWidgetData(
            topPriority: WidgetPriority(rank: 1, title: "Decide launch focus", whyItMatters: "Too many open loops", nextStep: "Pick one release priority"),
            priorities: [],
            date: "2026-04-09",
            updatedAt: .now
        )
    )
}
#Preview("Home Medium", as: .systemMedium) {
    CortexFocusWidget()
} timeline: {
    CortexEntry(
        date: .now,
        data: CortexWidgetData(
            topPriority: nil,
            priorities: [
                WidgetPriority(rank: 1, title: "Decide launch focus", whyItMatters: "", nextStep: "Pick one release priority"),
                WidgetPriority(rank: 2, title: "Tighten onboarding", whyItMatters: "", nextStep: "Cut one vague screen"),
                WidgetPriority(rank: 3, title: "Review ignored noise", whyItMatters: "", nextStep: "Keep only repeated signals"),
            ],
            date: "2026-04-09",
            updatedAt: .now
        )
    )
}
#endif
