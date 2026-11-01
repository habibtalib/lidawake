import AppKit
import LidAwakeCore
import SwiftUI

// MARK: - Theme

enum Theme {
    static let awake = LinearGradient(colors: [Color(red: 0.42, green: 0.36, blue: 1.0), Color(red: 0.16, green: 0.72, blue: 0.98)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
    static let asleep = LinearGradient(colors: [Color.gray.opacity(0.55), Color.gray.opacity(0.3)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
    static let accent = Color(red: 0.36, green: 0.45, blue: 1.0)
    static let card = Color.primary.opacity(0.055)
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.72)
}

// MARK: - Panel

struct PanelView: View {
    @EnvironmentObject private var model: AppModel
    @State private var customMinutes: Double = 90
    @State private var showCustom = false

    private var on: Bool { model.status.sleepDisabled }

    var body: some View {
        VStack(spacing: 12) {
            header

            if !model.status.permissionInstalled {
                SetupCard { model.installPermission() }
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                hero
                AgentModeCard()
                timerCard
                BatteryGuardCard(floor: $model.batteryFloor, battery: model.status.battery,
                                 activeFloor: on ? model.status.session?.batteryFloor : nil)
            }

            if on && !model.status.battery.onAC {
                Label("On battery with the lid closed, a Mac can get hot. Keep it out of bags.", systemImage: "thermometer.sun.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            footer
        }
        .padding(14)
        .frame(width: 320)
        .animation(Theme.spring, value: on)
        .animation(Theme.spring, value: model.status.permissionInstalled)
        .animation(Theme.spring, value: model.errorMessage)
        .onAppear { model.refresh() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(on ? AnyShapeStyle(Theme.awake) : AnyShapeStyle(Theme.asleep))
                    .frame(width: 26, height: 26)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: on)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("LidAwake").font(.system(size: 14, weight: .semibold))
                Text(on ? "Keeping your Mac awake" : "Sleeping normally")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            Spacer()
            BatteryPill(battery: model.status.battery)
        }
    }

    // MARK: Hero (power button + countdown)

    private var hero: some View {
        HStack(spacing: 16) {
            PowerButton(on: on, progress: model.timerProgress) {
                on ? model.turnOff() : model.turnOn(minutes: nil)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(on ? "Awake" : "Off")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Group {
                    if on, let deadline = model.status.session?.deadline {
                        HStack(spacing: 4) {
                            Image(systemName: "timer")
                            Text(timerInterval: Date()...max(Date(), deadline), countsDown: true)
                                .monospacedDigit()
                        }
                        .foregroundStyle(Theme.accent)
                    } else if on, model.status.session?.origin == .agent {
                        Label("For Claude Code", systemImage: "sparkles")
                            .foregroundStyle(Theme.accent)
                    } else if on {
                        Label("Until you turn it off", systemImage: "infinity")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Lid closed = sleep")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 12, weight: .medium))

                if on, model.status.session?.deadline != nil {
                    HStack(spacing: 6) {
                        ChipButton(title: "+30m", systemImage: "plus") { model.extend(minutes: 30) }
                        ChipButton(title: "+1h", systemImage: "plus") { model.extend(minutes: 60) }
                    }
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                } else if on, let origin = model.status.session?.origin {
                    Text("Started from \(origin.rawValue)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(on ? AnyShapeStyle(Theme.awake.opacity(0.6)) : AnyShapeStyle(Color.primary.opacity(0.06)), lineWidth: 1)
        )
    }

    // MARK: Timer card

    private var timerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(on ? "Change timer" : "Keep awake for", systemImage: "clock")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation(Theme.spring) { showCustom.toggle() }
                } label: {
                    Image(systemName: showCustom ? "chevron.up" : "slider.horizontal.3")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .help("Custom duration")
            }

            HStack(spacing: 6) {
                ForEach(AppModel.presets, id: \.label) { preset in
                    PresetChip(label: preset.label, selected: isSelected(preset.minutes)) {
                        model.turnOn(minutes: preset.minutes)
                    }
                }
            }

            if showCustom {
                VStack(spacing: 6) {
                    HStack {
                        Text(Duration.format(customMinutes * 60))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Spacer()
                        Button("Start") { model.turnOn(minutes: Int(customMinutes)) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(Theme.accent)
                    }
                    Slider(value: $customMinutes, in: 15...720, step: 15)
                        .tint(Theme.accent)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// A preset counts as selected when the running timer was started with that length (±1 minute).
    private func isSelected(_ minutes: Int?) -> Bool {
        guard on, let session = model.status.session else { return false }
        guard let minutes else { return session.deadline == nil }
        guard let deadline = session.deadline else { return false }
        return abs(deadline.timeIntervalSince(session.startedAt) - Double(minutes * 60)) < 61
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 4) {
            Button { SettingsWindow.open() } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(FooterButtonStyle())
            .keyboardShortcut(",", modifiers: .command)
            Spacer()
            Button { NSApp.terminate(nil) } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(FooterButtonStyle())
        }
    }
}

// MARK: - Agent mode and auto-off

struct AgentModeCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var expanded = false

    private static let durations = [0, 5, 10, 15, 30, 60, 120]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(model.agentBusy ? AnyShapeStyle(Theme.awake) : AnyShapeStyle(Color.primary.opacity(0.08)))
                        .frame(width: 30, height: 30)
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(model.agentBusy ? .white : .secondary)
                        .symbolEffect(.pulse, isActive: model.agentBusy)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Agent mode").font(.system(size: 12.5, weight: .semibold))
                    Text(model.agentStatusLine)
                        .font(.system(size: 11))
                        .foregroundStyle(model.agentBusy ? Theme.accent : .secondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
                Spacer()
                PillSwitch(isOn: model.rules.agentMode) { value in model.updateRules { $0.agentMode = value } }
            }

            Button {
                withAnimation(Theme.spring) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "moon.zzz")
                    Text(autoOffSummary).lineLimit(1)
                        .help("Sleep comes back on after this much agent quiet, keyboard and mouse idle, or network downtime")
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 8) {
                    if model.rules.agentMode {
                        ruleRow("Agent sessions end after quiet", "sparkles", \.agentQuietMinutes, allowOff: false)
                    }
                    ruleRow("Claude Code quiet", "bubble.left.and.text.bubble.right", \.offWhenAgentsQuietMinutes)
                    ruleRow("No keyboard or mouse", "keyboard", \.offWhenIdleMinutes)
                    ruleRow(model.networkDownSince == nil ? "Network down" : "Network down (now)", "wifi.slash", \.offWhenNetworkDownMinutes)
                    if !model.hooksInstalled {
                        Button {
                            model.installHooks()
                        } label: {
                            Label("Install Claude Code hooks for instant detection", systemImage: "link.badge.plus")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(model.rules.agentMode ? AnyShapeStyle(Theme.awake.opacity(0.45)) : AnyShapeStyle(Color.clear), lineWidth: 1)
        )
        .animation(Theme.spring, value: model.agentBusy)
        .animation(Theme.spring, value: model.rules.agentMode)
    }

    private var autoOffSummary: String {
        let r = model.rules
        let parts = [r.offWhenAgentsQuietMinutes > 0 ? "\(r.offWhenAgentsQuietMinutes)m quiet" : nil,
                     r.offWhenIdleMinutes > 0 ? "\(r.offWhenIdleMinutes)m idle" : nil,
                     r.offWhenNetworkDownMinutes > 0 ? "\(r.offWhenNetworkDownMinutes)m offline" : nil].compactMap { $0 }
        return parts.isEmpty ? "only when you say" : parts.joined(separator: " · ")
    }

    private func ruleRow(_ title: String, _ symbol: String, _ key: WritableKeyPath<AutoRules, Int>, allowOff: Bool = true) -> some View {
        HStack {
            Label(title, systemImage: symbol)
                .font(.system(size: 11.5))
            Spacer()
            Menu {
                ForEach(Self.durations.filter { allowOff || $0 > 0 }, id: \.self) { minutes in
                    Button(minutes == 0 ? "Off" : Duration.format(Double(minutes) * 60)) {
                        model.updateRules { $0[keyPath: key] = minutes }
                    }
                }
            } label: {
                Text(model.rules[keyPath: key] == 0 ? "Off" : Duration.format(Double(model.rules[keyPath: key]) * 60))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(model.rules[keyPath: key] == 0 ? .secondary : Theme.accent)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

// MARK: - Components

/// A SwiftUI-only switch (renders in snapshots, animates with the app's spring).
struct PillSwitch: View {
    let isOn: Bool
    let set: (Bool) -> Void

    var body: some View {
        Button { set(!isOn) } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? AnyShapeStyle(Theme.awake) : AnyShapeStyle(Color.primary.opacity(0.15)))
                    .frame(width: 38, height: 22)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                    .frame(width: 18, height: 18)
                    .padding(2)
            }
        }
        .buttonStyle(.plain)
        .animation(Theme.spring, value: isOn)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// Big round toggle. Shows a countdown ring while a timer runs and breathes while awake.
struct PowerButton: View {
    let on: Bool
    let progress: Double?
    let action: () -> Void
    @State private var hovering = false
    @State private var pressed = false
    @State private var breathe = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(on ? AnyShapeStyle(Theme.awake) : AnyShapeStyle(Color.primary.opacity(0.08)))
                    .shadow(color: on ? Theme.accent.opacity(breathe ? 0.55 : 0.25) : .clear, radius: breathe ? 16 : 8)

                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 4)
                    .padding(-6)
                if let progress {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Theme.awake, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(-6)
                        .animation(.linear(duration: 1), value: progress)
                }

                Image(systemName: on ? "sun.max.fill" : "moon.zzz.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(on ? .white : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 72, height: 72)
            .scaleEffect(pressed ? 0.92 : (hovering ? 1.04 : 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in withAnimation(.easeOut(duration: 0.1)) { pressed = true } }
            .onEnded { _ in withAnimation(Theme.spring) { pressed = false } })
        .animation(Theme.spring, value: hovering)
        .onAppear { startBreathing() }
        .onChange(of: on) { startBreathing() }
        .help(on ? "Let the Mac sleep again" : "Keep awake with the lid closed")
        .accessibilityLabel(on ? "Turn off LidAwake" : "Turn on LidAwake")
    }

    private func startBreathing() {
        breathe = false
        guard on else { return }
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathe = true }
    }
}

struct PresetChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .foregroundStyle(selected ? .white : .primary)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? AnyShapeStyle(Theme.awake) : AnyShapeStyle(Color.primary.opacity(hovering ? 0.12 : 0.07)))
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.spring, value: selected)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

struct ChipButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var bump = 0

    var body: some View {
        Button {
            bump += 1
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10.5, weight: .semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Theme.accent.opacity(0.15), in: Capsule())
                .foregroundStyle(Theme.accent)
                .symbolEffect(.bounce, value: bump)
        }
        .buttonStyle(.plain)
    }
}

/// Battery bar with the guard threshold drawn on it; tap a level or Off.
struct BatteryGuardCard: View {
    @Binding var floor: Int
    let battery: BatteryStatus
    let activeFloor: Int?
    private let levels = [0, 10, 20, 30]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Battery guard", systemImage: "shield.lefthalf.filled")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(floor == 0 ? "Off" : "Stops at \(floor)%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(floor == 0 ? .secondary : Theme.accent)
                    .contentTransition(.numericText())
            }

            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    if let percent = battery.percent {
                        Capsule()
                            .fill(LinearGradient(colors: [percentColor(percent).opacity(0.7), percentColor(percent)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: width * CGFloat(percent) / 100)
                    }
                    if floor > 0 {
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 2, height: 14)
                            .offset(x: width * CGFloat(floor) / 100 - 1)
                            .transition(.opacity)
                    }
                }
                .frame(height: 8)
                .frame(maxHeight: .infinity)
            }
            .frame(height: 14)
            .animation(Theme.spring, value: floor)

            HStack(spacing: 6) {
                ForEach(levels, id: \.self) { level in
                    PresetChip(label: level == 0 ? "Off" : "\(level)%", selected: floor == level) {
                        withAnimation(Theme.spring) { floor = level }
                    }
                }
            }

            if let activeFloor, activeFloor != floor {
                Text("This session stops at \(activeFloor)%. The new level applies next time.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func percentColor(_ percent: Int) -> Color {
        percent <= 20 ? .red : percent <= 40 ? .orange : .green
    }
}

struct BatteryPill: View {
    let battery: BatteryStatus

    var body: some View {
        if let percent = battery.percent {
            HStack(spacing: 4) {
                Image(systemName: battery.onAC ? "battery.100.bolt" : symbol(percent))
                    .symbolRenderingMode(.hierarchical)
                Text("\(percent)%").monospacedDigit()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(percent <= 20 && !battery.onAC ? .red : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.06), in: Capsule())
        }
    }

    private func symbol(_ percent: Int) -> String {
        switch percent {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}

struct SetupCard: View {
    let install: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.awake)
                VStack(alignment: .leading, spacing: 2) {
                    Text("One-time setup").font(.system(size: 13, weight: .semibold))
                    Text("Allow LidAwake to run only `pmset -a disablesleep 1` and `0`.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(action: install) {
                Label("Install permission", systemImage: "key.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct FooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FooterButton(configuration: configuration)
    }

    private struct FooterButton: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(hovering ? .primary : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(hovering ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 6))
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            LabeledContent("Permission") {
                if model.status.permissionInstalled {
                    HStack {
                        Text("Installed").foregroundStyle(.secondary)
                        Button("Remove") {
                            model.turnOff()
                            try? SudoersRule.uninstall()
                            model.refresh()
                        }
                    }
                } else {
                    Button("Install") { model.installPermission() }
                }
            }
            LabeledContent("Claude Code hooks") {
                if model.hooksInstalled {
                    HStack {
                        Text("Installed").foregroundStyle(.secondary)
                        Button("Remove") {
                            try? ClaudeHooks.uninstall()
                            model.refresh()
                        }
                    }
                } else {
                    Button("Install") { model.installHooks() }
                }
            }
            LabeledContent("Rule file", value: SudoersRule.path)
            LabeledContent("Version", value: LidAwakeVersion.string)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear { model.refresh() }
    }
}
