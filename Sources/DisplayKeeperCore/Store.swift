import Foundation

/// Saved profiles, one per set of monitors, in a JSON file.
public final class ProfileStore: @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()

    public static var defaultURL: URL {
        if let path = ProcessInfo.processInfo.environment["DISPLAY_KEEPER_PROFILES"] { return URL(fileURLWithPath: path) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DisplayKeeper/profiles.json")
    }

    public init(url: URL = ProfileStore.defaultURL) {
        self.url = url
    }

    public func all() -> [String: Profile] {
        lock.lock(); defer { lock.unlock() }
        return read()
    }

    public func profile(for keys: [String]) -> Profile? {
        all()[Profile.id(for: keys)]
    }

    public func save(_ profile: Profile) throws {
        try mutate { $0[profile.id] = profile }
    }

    public func remove(id: String) throws {
        try mutate { $0.removeValue(forKey: id) }
    }

    private func mutate(_ change: (inout [String: Profile]) -> Void) throws {
        lock.lock(); defer { lock.unlock() }
        var profiles = read()
        change(&profiles)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(profiles).write(to: url, options: .atomic)
    }

    private func read() -> [String: Profile] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: Profile].self, from: data)) ?? [:]
    }
}
