import SwiftUI

struct HelpView: View {
    @State private var selection: HelpSection.ID? = HelpSection.all.first?.id

    var body: some View {
        HStack(spacing: 0) {
            List(HelpSection.all, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol).tag(section.id)
            }
            .listStyle(.sidebar)
            .frame(width: 210)

            Divider()

            ScrollView {
                if let section = HelpSection.all.first(where: { $0.id == selection }) {
                    HelpSectionView(section: section)
                        .id(section.id)
                }
            }
            .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 440, idealHeight: 560)
    }
}

private struct HelpSectionView: View {
    let section: HelpSection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(section.title, systemImage: section.symbol)
                .font(.title2.weight(.semibold))
                .labelStyle(TitleIconLabelStyle())
                .padding(.bottom, 2)
            ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: 600, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: HelpBlock) -> some View {
        switch block {
        case .heading(let text):
            Text(text).font(.headline).padding(.top, 6)
        case .paragraph(let text):
            Text(markdown(text)).fixedSize(horizontal: false, vertical: true).lineSpacing(2)
        case .steps(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(i + 1).").monospacedDigit().foregroundStyle(.secondary).frame(width: 18, alignment: .trailing)
                        Text(markdown(item)).fixedSize(horizontal: false, vertical: true).lineSpacing(2)
                    }
                }
            }
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary).frame(width: 18, alignment: .trailing)
                        Text(markdown(item)).fixedSize(horizontal: false, vertical: true).lineSpacing(2)
                    }
                }
            }
        case .code(let text):
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            .background(codeBackground)
        case .commands(let rows):
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        Text(row.0).font(.system(.callout, design: .monospaced)).fixedSize()
                        Text(row.1).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(codeBackground)
        case .note(let text):
            Label { Text(markdown(text)).fixedSize(horizontal: false, vertical: true) } icon: {
                Image(systemName: "info.circle.fill").foregroundStyle(Color.accentColor)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.08)))
        }
    }

    private var codeBackground: some View {
        RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

private struct TitleIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon.foregroundStyle(Color.accentColor)
            configuration.title
        }
    }
}

enum HelpBlock {
    case heading(String)
    case paragraph(String)
    case steps([String])
    case bullets([String])
    case code(String)
    case commands([(String, String)])
    case note(String)
}

struct HelpSection: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let blocks: [HelpBlock]

    static let all: [HelpSection] = [
        HelpSection(id: "start", title: "Getting Started", symbol: "play.circle", blocks: [
            .paragraph("Display Keeper remembers where your monitors are, and optionally where your windows are, and puts them back after the Mac wakes, unlocks or sees a display change. It lives in the menu bar and has no Dock icon."),
            .steps([
                "Arrange your monitors in **System Settings → Displays**, and place your windows where you like them.",
                "Click the Display Keeper icon in the menu bar and choose **Save Current Layout**. Nothing is saved automatically, so save again whenever you change your setup.",
                "Turn on **Open at Login** (in the menu or in Settings → General) so Display Keeper is always running.",
                "To have windows put back as well, turn on **Restore Windows** and allow Accessibility access when asked.",
            ]),
            .paragraph("A layout belongs to one set of monitors. If you use several desks, repeat steps 1 and 2 at each one; Display Keeper recognises each set and uses the right layout. You can see and delete saved layouts in **Settings → Layouts**."),
        ]),
        HelpSection(id: "how", title: "How It Works", symbol: "gearshape.2", blocks: [
            .heading("Why identical monitors get swapped"),
            .paragraph("Identical monitors often report the same serial number to macOS, so after sleep macOS cannot tell them apart and may hand out their positions in whatever order they come up. The left screen's windows and menu bar end up on the right one."),
            .paragraph("Display Keeper identifies each monitor by its **per-unit serial** (for example `HTPM100050`), which is unique even when the numeric serial is shared. If a monitor has no per-unit serial, it uses the numeric serial when that is unique, and otherwise the port the monitor is plugged into."),
            .heading("When a layout is restored"),
            .bullets([
                "After any display change or wake, once the displays have been quiet for the delay set in **Settings → General** (4 seconds by default).",
                "After you unlock the Mac (1 second by default).",
                "When Display Keeper starts.",
                "Whenever you choose **Restore Saved Layout** from the menu, even while automatic restore is paused.",
            ]),
            .paragraph("Each time, Display Keeper compares the current position and resolution of every monitor with the saved layout. If anything differs it rearranges all of them in one step; if they already match it leaves the displays alone. If a saved resolution is no longer offered, it uses the same resolution at the closest refresh rate."),
            .heading("How windows are matched"),
            .paragraph("When Restore Windows is on, windows are checked on every pass, because macOS can move them even when the displays came back in the right order. Each saved window is matched to an open one in this order:"),
            .steps([
                "**The same window**, if its app has kept running since you saved.",
                "**The same app and window title.**",
                "**The same app and the window's position** in that app's list of windows.",
            ]),
            .paragraph("Each open window is used at most once. Windows that match nothing are left alone. A matched window is moved back to the monitor it was on and given its saved size and position on that monitor; windows that are already within a few points of their spot are not touched."),
        ]),
        HelpSection(id: "limits", title: "What Is Not Restored", symbol: "eye.slash", blocks: [
            .bullets([
                "**Minimised windows** are skipped, both when saving and when restoring.",
                "**Full-screen windows** are skipped.",
                "**Windows on other Spaces**: only windows on the current Space of each monitor can be seen and moved.",
                "**Mirrored displays** are left as they are; only the main display of a mirrored set is arranged. Rotation is not managed either.",
                "**Windows that are not standard app windows**, such as panels, palettes and menu-bar apps' popovers.",
                "**Windows of apps that were not running** when Display Keeper restored. They are moved on the next pass, for example after the next unlock or wake.",
            ]),
        ]),
        HelpSection(id: "accessibility", title: "Accessibility Permission", symbol: "hand.raised", blocks: [
            .paragraph("Reading and moving other apps' windows goes through the macOS Accessibility interface, which needs your permission. Without it Display Keeper still restores monitor positions, but it cannot save or move windows."),
            .heading("How to grant it"),
            .steps([
                "Open **Settings → General** in Display Keeper and click **Open System Settings…** next to Accessibility. (Or open **System Settings → Privacy & Security → Accessibility** yourself.)",
                "Turn on **Display Keeper**. If it is not in the list, click **+** and choose it from your Applications folder.",
                "Return to Display Keeper. The General tab shows **Allowed** once the permission is in effect.",
            ]),
            .note("Builds that are not signed with a Developer ID, including ones you build yourself, look like a new app to macOS after every update. If windows stop moving after an update, remove Display Keeper from the Accessibility list with **−** and add it again."),
        ]),
        HelpSection(id: "cli", title: "Command Line", symbol: "terminal", blocks: [
            .paragraph("The app includes a command-line tool that uses the same saved layouts. Run it with one of the commands below, for example `display-keeper status`."),
            .code("/Applications/DisplayKeeper.app/Contents/Resources/display-keeper"),
            .commands([
                ("list", "Online displays and the key each is saved under."),
                ("save", "Save displays and windows for this set of monitors."),
                ("windows", "List open windows as they would be saved."),
                ("restore", "Re-apply the saved layout now."),
                ("status", "Compare the current arrangement with the saved one."),
                ("profiles", "List saved layouts."),
                ("forget", "Delete the layout for the current monitors."),
                ("watch", "Run headless, for example from a LaunchAgent, instead of the menu-bar app."),
            ]),
            .paragraph("Layouts are stored in `~/Library/Application Support/DisplayKeeper/profiles.json`. To save or list windows from Terminal, the terminal app itself needs Accessibility access."),
        ]),
        HelpSection(id: "trouble", title: "Troubleshooting", symbol: "wrench.and.screwdriver", blocks: [
            .heading("Nothing happens after wake"),
            .bullets([
                "Open the menu: the first line should say **Layout matches** or **Layout differs from saved**. If it says **No layout saved for these displays**, arrange your monitors and choose **Save Current Layout**.",
                "If it says **Paused**, turn off **Pause Automatic Restore**.",
                "A layout only applies to exactly the same set of monitors. Connecting or disconnecting one, including the built-in display when you open or close the lid, is a different set with its own layout.",
                "If your monitors take long to wake, increase the delay after a display change in **Settings → General**.",
            ]),
            .heading("Monitors are restored but windows do not move"),
            .bullets([
                "Check that **Restore Windows** is on and that Accessibility shows **Allowed** in **Settings → General**. After an update, you may need to add Display Keeper to the Accessibility list again.",
                "Windows are saved together with the layout. If Restore Windows was off when you saved, save the layout again. **Settings → Layouts → Show Windows…** lists what was saved.",
                "Minimised, full-screen and other-Space windows are never moved.",
            ]),
            .heading("Start over"),
            .paragraph("Choose **Forget Layout for These Displays** from the menu (or delete the layout in **Settings → Layouts**), arrange everything again, and choose **Save Current Layout**."),
        ]),
    ]
}
