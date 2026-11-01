import AppKit
import LidAwakeCore
import SwiftUI

struct PanelView: View {
    @EnvironmentObject private var model: AppModel

    private var on: Bool { model.status.sleepDisabled }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !model.status.permissionInstalled {
                permissionCard
            } else {
                Toggle(isOn: Binding(get: { on }, set: { $0 ? model.turnOn(minutes: nil) : model.turnOff() })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stay awake with lid closed").font(.headline)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                VStack(alignment: .leading, spacing: 6) {
                    Text(on ? "Change timer" : "Turn on for").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(AppModel.presets, id: \.label) { preset in
                            Button(preset.label) { model.turnOn(minutes: preset.minutes) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }

                Picker("Battery guard", selection: $model.batteryFloor) {
                    Text("Off").tag(0)
                    Text("10%").tag(10)
                    Text("20%").tag(20)
                    Text("30%").tag(30)
                }
                .pickerStyle(.segmented)
                .help("Turn sleep back on when running on battery at or below this level. Applies to the next session.")
            }

            if on && !model.status.battery.onAC {
                Label("On battery with the lid closed the Mac can get hot. Avoid bags and sleeves.", systemImage: "thermometer.sun")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            HStack {
                SettingsLink { Text("Settings…") }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { model.refresh() }
    }

    private var header: some View {
        HStack {
            Image(systemName: on ? "laptopcomputer.trianglebadge.exclamationmark" : "laptopcomputer")
                .font(.title2)
                .foregroundStyle(on ? Color.accentColor : .secondary)
            Text("LidAwake").font(.title3.bold())
            Spacer()
            if let percent = model.status.battery.percent {
                Label("\(percent)%", systemImage: model.status.battery.onAC ? "battery.100.bolt" : "battery.50")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String {
        guard on else { return "Off: the Mac sleeps when the lid closes." }
        var parts: [String] = []
        if let left = model.remaining { parts.append("\(Duration.format(left)) left") } else { parts.append("Until you turn it off") }
        if let floor = model.status.session?.batteryFloor { parts.append("stops at \(floor)% battery") }
        return parts.joined(separator: " · ")
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("One-time setup").font(.headline)
            Text("LidAwake needs permission to run `pmset -a disablesleep 1` and `0`. You'll be asked for your admin password once; nothing else is allowed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Install Permission") { model.installPermission() }
                .buttonStyle(.borderedProminent)
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
            LabeledContent("Rule file", value: SudoersRule.path)
            LabeledContent("Version", value: LidAwakeVersion.string)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear { model.refresh() }
    }
}
