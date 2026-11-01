import AppIntents
import LidAwakeCore
import SwiftUI
import WidgetKit

// The widget is sandboxed and cannot run sudo. A tap writes a WidgetRequest to the App Group
// container and posts a Darwin notification; the LidAwake app carries it out and refreshes the widget.

enum RequestSender {
    static func send(_ request: WidgetRequest) {
        if let url = WidgetBridge.requestURL { try? WidgetBridge.write(request, to: url) }
        Signal.post(.request)
    }
}

struct ToggleLidAwakeIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle LidAwake"
    static var description = IntentDescription("Keep the Mac awake with the lid closed, or let it sleep again.")

    func perform() async throws -> some IntentResult {
        RequestSender.send(WidgetRequest(action: .toggle))
        return .result()
    }
}

struct LidAwakeForIntent: AppIntent {
    static var title: LocalizedStringResource = "Keep Awake For"

    @Parameter(title: "Minutes") var minutes: Int

    init() {}
    init(minutes: Int) { self.minutes = minutes }

    func perform() async throws -> some IntentResult {
        RequestSender.send(WidgetRequest(action: .on, minutes: minutes))
        return .result()
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(context.isPreview ? Entry(date: Date(), snapshot: .placeholder) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = current()
        var next = Date().addingTimeInterval(15 * 60)
        if let deadline = entry.snapshot?.deadline, deadline > Date(), deadline < next { next = deadline.addingTimeInterval(5) }
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func current() -> Entry {
        Entry(date: Date(), snapshot: WidgetBridge.snapshotURL.flatMap { WidgetBridge.read(WidgetSnapshot.self, from: $0) })
    }
}

struct LidAwakeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, snapshot.appLooksAlive(now: entry.date) {
                content(snapshot)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "laptopcomputer").font(.title)
                    Text("Open LidAwake").font(.caption.bold())
                    Text("The menu bar app applies widget taps.").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .widgetURL(WidgetBridge.panelURL)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder private func content(_ s: WidgetSnapshot) -> some View {
        if !s.permissionInstalled {
            VStack(spacing: 6) {
                Image(systemName: "lock").font(.title2)
                Text("Set up LidAwake").font(.caption.bold())
            }
            .widgetURL(WidgetBridge.panelURL)
        } else if family == .systemSmall {
            small(s)
        } else {
            HStack(spacing: 16) {
                small(s)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Keep awake for").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach([30, 60, 120], id: \.self) { m in
                            Button(intent: LidAwakeForIntent(minutes: m)) {
                                Text(m < 60 ? "\(m)m" : "\(m / 60)h").font(.caption.bold())
                            }
                        }
                    }
                    if let floor = s.batteryFloor, s.sleepDisabled {
                        Text("Stops at \(floor)% battery").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func small(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: s.sleepDisabled ? "laptopcomputer.trianglebadge.exclamationmark" : "laptopcomputer")
                    .font(.title2)
                    .foregroundStyle(s.sleepDisabled ? Color.accentColor : .secondary)
                Spacer()
                if let percent = s.battery.percent {
                    Text("\(percent)%").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(s.sleepDisabled ? "Awake" : "Sleeps normally").font(.headline)
            if s.sleepDisabled, let deadline = s.deadline, deadline > entry.date {
                Text(deadline, style: .timer).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            } else {
                Text(s.sleepDisabled ? "Until turned off" : "Lid closed = sleep").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(intent: ToggleLidAwakeIntent()) {
                Text(s.sleepDisabled ? "Turn Off" : "Turn On").font(.caption.bold()).frame(maxWidth: .infinity)
            }
            .tint(s.sleepDisabled ? .red : .accentColor)
        }
    }
}

@main
struct LidAwakeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetBridge.kind, provider: Provider()) { entry in
            LidAwakeWidgetView(entry: entry)
        }
        .configurationDisplayName("LidAwake")
        .description("Keep your Mac awake with the lid closed.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
