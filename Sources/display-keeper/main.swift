import AppKit
import DisplayKeeperCore
import Foundation

let usage = """
usage: display-keeper <command>

  list       show online displays and the stable key each is saved under
  save       save the current arrangement for this set of monitors
  restore    re-apply the saved arrangement now
  status     compare the current arrangement with the saved one
  profiles   list saved profiles
  forget     delete the profile for the current set of monitors
  watch      stay running and restore after wake, unlock and display changes
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func row(_ p: Placement) -> String {
    "\(p.name.padding(toLength: 26, withPad: " ", startingAt: 0)) \(p.mode.description.padding(toLength: 24, withPad: " ", startingAt: 0)) (\(p.x), \(p.y))  \(p.key)"
}

@MainActor
func run() {
    let store = ProfileStore()
    let keeper = Keeper(store: store)
    if CommandLine.arguments.dropFirst().first != "watch" { keeper.log = { _ in } }
    switch CommandLine.arguments.dropFirst().first {
    case "list":
        for d in SystemDisplays.online() { print(row(d.placement)) }
    case "save":
        do {
            let profile = try keeper.saveCurrent()
            print("saved layout for \(profile.placements.count) displays:")
            profile.placements.forEach { print("  " + row($0)) }
        } catch { fail("could not save: \(error)") }
    case "restore":
        switch keeper.restore(force: true) {
        case .noProfile: fail("no saved layout for this set of monitors; arrange them and run: display-keeper save")
        case .failed(let why): fail(why)
        case .alreadyCorrect: print("already correct")
        case .restored(let n): print("restored \(n) display(s)")
        case .paused: break
        }
    case "status":
        let online = SystemDisplays.online().map(\.placement)
        guard let profile = store.profile(for: online.map(\.key)) else { fail("no saved layout for this set of monitors") }
        let diff = profile.differences(from: online) ?? []
        if diff.isEmpty { print("matches saved layout") } else {
            print("differs from saved layout:")
            diff.forEach { print("  want " + row($0)) }
        }
    case "profiles":
        for (id, p) in store.all().sorted(by: { $0.key < $1.key }) {
            print("\(id)  (saved \(p.savedAt.formatted()))")
            p.placements.forEach { print("  " + row($0)) }
        }
    case "forget":
        let id = Profile.id(for: SystemDisplays.online().map(\.placement.key))
        do { try store.remove(id: id); print("forgot \(id)") } catch { fail("\(error)") }
    case "watch":
        _ = NSApplication.shared
        keeper.start()
        print("watching displays; profiles in \(store.url.path)")
        RunLoop.main.run()
    default:
        fail(usage)
    }
}

MainActor.assumeIsolated { run() }
