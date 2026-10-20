import AppKit
import DisplayKeeperCore
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Open at Login", isOn: Binding(get: { settings.opensAtLogin }, set: { settings.setOpensAtLogin($0) }))
                if settings.loginStatus == .requiresApproval {
                    note("Approve Display Keeper in System Settings → General → Login Items.", systemImage: "exclamationmark.triangle.fill", tint: .orange)
                }
                if let error = settings.loginError {
                    note(error, systemImage: "exclamationmark.triangle.fill", tint: .orange)
                }
                Toggle(isOn: $settings.isPaused) {
                    Text("Pause Automatic Restore")
                    Text("Layouts are not restored after wake, unlock or display changes. Restore Saved Layout in the menu still works.")
                }
            }

            Section {
                Toggle(isOn: $settings.restoresWindows) {
                    Text("Restore Windows")
                    Text("Save window positions with each layout and move windows back to their monitor.")
                }
                LabeledContent("Accessibility") {
                    if settings.isTrusted {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        HStack(spacing: 8) {
                            Label("Not allowed", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                            Button("Open System Settings…") { AppSettings.openAccessibilitySettings() }
                        }
                    }
                }
            } footer: {
                if !settings.isTrusted {
                    Text("Moving other apps' windows needs Accessibility access. Turn on Display Keeper in Privacy & Security → Accessibility.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Section {
                delayRow("After a display change or wake", value: $settings.settleDelay, range: AppSettings.settleRange,
                         help: "Monitors come up one by one. Wait this long after the last change before restoring.")
                delayRow("After unlock", value: $settings.unlockDelay, range: AppSettings.unlockRange,
                         help: "Monitors are usually ready by the time you unlock.")
            } header: {
                Text("Wait Before Restoring")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in settings.refresh() }
        // Granting access in System Settings does not bring this app back to the front, so poll.
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in settings.refresh() }
        .onAppear { settings.refresh() }
    }

    private func delayRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, help: String) -> some View {
        LabeledContent {
            Stepper(value: value, in: range, step: range.lowerBound == 0 ? 0.5 : 1) {
                Text(seconds(value.wrappedValue))
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .trailing)
            }
        } label: {
            Text(title)
            Text(help)
        }
    }

    private func seconds(_ v: Double) -> String {
        v == v.rounded() ? "\(Int(v)) s" : String(format: "%.1f s", v)
    }

    private func note(_ text: String, systemImage: String, tint: Color) -> some View {
        Label { Text(text).foregroundStyle(.secondary) } icon: { Image(systemName: systemImage).foregroundStyle(tint) }
            .font(.callout)
    }
}

struct LayoutsSettingsView: View {
    @ObservedObject var layouts: LayoutsModel
    @ObservedObject var settings: AppSettings
    @State private var selection: String?
    @State private var showingWindows: LayoutsModel.Item?
    @State private var confirmingDelete: LayoutsModel.Item?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Display Keeper keeps one layout per set of monitors and picks the right one automatically.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(selection: $selection) {
                ForEach(layouts.items) { item in
                    LayoutRow(item: item)
                        .tag(item.id)
                        .contextMenu {
                            Button("Show Windows…") { showingWindows = item }.disabled(item.profile.windows.isEmpty)
                            Divider()
                            Button("Delete…") { confirmingDelete = item }
                        }
                }
            }
            .listStyle(.inset)
            .overlay {
                if layouts.items.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "rectangle.3.group").font(.system(size: 28)).foregroundStyle(.tertiary)
                        Text("No Saved Layouts").font(.headline)
                        Text("Arrange your monitors and windows, then click Save Current Layout.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
            .onDeleteCommand { if let item = selectedItem { confirmingDelete = item } }
            .border(Color(nsColor: .separatorColor))

            HStack {
                Button {
                    do {
                        let p = try layouts.saveCurrent()
                        selection = p.id
                    } catch { errorMessage = String(describing: error) }
                } label: {
                    Label(layouts.current == nil ? "Save Current Layout" : "Save Current Layout (Replace)", systemImage: "square.and.arrow.down")
                }
                Spacer()
                Button("Show Windows…") { showingWindows = selectedItem }
                    .disabled(selectedItem?.profile.windows.isEmpty ?? true)
                Button("Delete…") { confirmingDelete = selectedItem }
                    .disabled(selectedItem == nil)
            }
            if settings.restoresWindows && !settings.isTrusted {
                Text("Accessibility access is not granted, so saving stores monitor positions only.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if !settings.restoresWindows {
                Text("Restore Windows is off, so saving stores monitor positions only.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 620, height: 420)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in layouts.reload() }
        .onAppear {
            layouts.reload()
            if selection == nil { selection = layouts.current?.id }
        }
        .sheet(item: $showingWindows) { item in WindowsSheet(item: item) }
        .confirmationDialog(
            "Delete this layout?",
            isPresented: Binding(get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } }),
            presenting: confirmingDelete
        ) { item in
            Button("Delete", role: .destructive) {
                do { try layouts.delete(id: item.id) } catch { errorMessage = String(describing: error) }
            }
        } message: { item in
            Text("The saved positions for \(item.profile.monitorSummary) will be removed. Display Keeper will stop restoring this set of monitors until you save again.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private var selectedItem: LayoutsModel.Item? { layouts.items.first { $0.id == selection } }
}

private struct LayoutRow: View {
    let item: LayoutsModel.Item

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.profile.placements.count > 2 ? "rectangle.3.group" : item.profile.placements.count == 2 ? "rectangle.split.2x1" : "display")
                .font(.title2)
                .foregroundStyle(item.isCurrent ? Color.accentColor : .secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.profile.monitorSummary).font(.body.weight(.medium)).lineLimit(2)
                    if item.isCurrent {
                        Text("Connected")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(item.profile.placementsLeftToRight.map(\.name).joined(separator: "  ·  "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .help(item.profile.placementsLeftToRight.map { "\($0.name): \($0.mode.description)" }.joined(separator: "\n"))
                Text("Saved \(item.profile.savedAt.formatted(date: .abbreviated, time: .shortened)) · \(windowCount)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var windowCount: String {
        let n = item.profile.windows.count
        return n == 0 ? "no windows" : n == 1 ? "1 window" : "\(n) windows"
    }
}

private struct WindowsSheet: View {
    let item: LayoutsModel.Item
    @Environment(\.dismiss) private var dismiss

    private struct Row: Identifiable {
        let id: Int
        let app: String
        let title: String
        let display: String
        let displayOrder: Int
        let size: String
    }

    private var rows: [Row] {
        let labels = item.profile.displayLabels
        let order = Dictionary(uniqueKeysWithValues: item.profile.placementsLeftToRight.enumerated().map { ($1.key, $0) })
        return item.profile.windows.enumerated().map { i, w in
            Row(id: i, app: w.appName, title: w.title.isEmpty ? "Untitled" : w.title,
                display: labels[w.displayKey] ?? w.displayKey, displayOrder: order[w.displayKey] ?? .max,
                size: "\(w.width) × \(w.height)")
        }
        .sorted {
            if $0.displayOrder != $1.displayOrder { return $0.displayOrder < $1.displayOrder }
            if $0.app != $1.app { return $0.app.localizedStandardCompare($1.app) == .orderedAscending }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Saved Windows").font(.headline)
                Text(item.profile.monitorSummary).foregroundStyle(.secondary)
            }
            Table(rows) {
                TableColumn("App", value: \.app).width(min: 80, ideal: 110)
                TableColumn("Window", value: \.title)
                TableColumn("Display", value: \.display).width(min: 90, ideal: 140)
                TableColumn("Size", value: \.size).width(min: 70, ideal: 84)
            }
            .border(Color(nsColor: .separatorColor))
            HStack {
                Text("Listed left to right by display. Windows are restored to the same size and spot on that display.")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 600, height: 400)
    }
}

struct UpdatesSettingsView: View {
    @ObservedObject var updater: UpdaterModel

    var body: some View {
        Group {
            if updater.isConfigured {
                Form {
                    Section {
                        Toggle("Automatically check for updates",
                               isOn: Binding(get: { updater.automaticallyChecks }, set: { updater.setAutomaticallyChecks($0) }))
                        Toggle("Automatically download and install updates",
                               isOn: Binding(get: { updater.automaticallyDownloads }, set: { updater.setAutomaticallyDownloads($0) }))
                            .disabled(!updater.automaticallyChecks || !updater.allowsAutomaticUpdates)
                    }
                    Section {
                        LabeledContent("Current version", value: AppInfo.versionDescription)
                        LabeledContent("Last checked") {
                            if let date = updater.lastCheck {
                                Text(date.formatted(date: .abbreviated, time: .shortened))
                            } else {
                                Text("Never").foregroundStyle(.secondary)
                            }
                        }
                        HStack {
                            Spacer()
                            Button("Check Now") { updater.checkForUpdates() }
                                .disabled(!updater.canCheck)
                        }
                    }
                }
                .formStyle(.grouped)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Updates Are Not Configured").font(.headline)
                    Text("This build has no update feed, so it cannot check for updates. Download new versions from the Releases page.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Link("Open Releases Page", destination: AppInfo.releases)
                    Text(AppInfo.versionDescription).font(.caption).foregroundStyle(.tertiary)
                }
                .padding(30)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}
