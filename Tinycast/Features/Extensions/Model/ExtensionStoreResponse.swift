import Foundation

/// Someone else's endpoint, so every field an install doesn't need is optional.
enum ExtensionStoreResponse {
    /// The endpoint the store's own site searches with; unofficial, so it can change unannounced.
    static func searchURL(query: String, page: Int) -> URL? {
        var components = URLComponents(string: "https://www.raycast.com/frontend_api/extensions/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: String(page)),
            // Case-sensitive: any other spelling returns only extensions listing no platforms.
            URLQueryItem(name: "platform", value: "macOS")
        ]
        return components?.url
    }

    static func browseURL(page: Int) -> URL? {
        var components = URLComponents(string: "https://www.raycast.com/frontend_api/extensions")
        components?.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "platform", value: "macOS")
        ]
        return components?.url
    }

    static func lookupURL(handle: String, name: String) -> URL? {
        guard !handle.isEmpty, !name.isEmpty else { return nil }
        return URL(string: "https://www.raycast.com/api/v1/extensions")?
            .appending(path: handle)
            .appending(path: name)
    }

    private struct StorePayload: Decodable {
        let data: [StoreEntry]
        let totalResults: Int?

        enum CodingKeys: String, CodingKey {
            case data
            case totalResults = "total_results"
        }
    }

    private struct StoreEntry: Decodable {
        let id: String
        let name: String
        let title: String?
        let description: String?
        let author: Author?
        let icons: Icons?
        let commands: [Command]?
        let downloadCount: Int?
        let downloadURL: String?
        let commitSHA: String?
        let status: String?
        let categories: [String]?
        let updatedAt: TimeInterval?
        let storeURL: String?
        let readmeURL: String?
        let metadata: [String]?
        let changelog: Changelog?

        struct Author: Decodable {
            let name: String?
            let handle: String?
        }
        struct Icons: Decodable {
            let light: String?
            let dark: String?
        }
        struct Command: Decodable {
            let name: String?
            let title: String?
            let description: String?
        }
        struct Changelog: Decodable {
            let versions: [Version]?
        }
        struct Version: Decodable {
            let title: String?
            let date: String?
            let markdown: String?
        }

        enum CodingKeys: String, CodingKey {
            case id, name, title, description, author, icons, commands, status, categories, metadata
            case changelog
            case downloadCount = "download_count"
            case downloadURL = "download_url"
            case commitSHA = "commit_sha"
            case updatedAt = "updated_at"
            case storeURL = "store_url"
            case readmeURL = "readme_url"
        }
    }

    static func parseStore(_ data: Data) throws -> [ExtensionListing] {
        try JSONDecoder().decode(StorePayload.self, from: data).data.compactMap(listing(from:))
    }

    /// `rawCount` is what the endpoint sent, before dropped entries, because paging counts that.
    static func parsePage(_ data: Data) throws -> ExtensionStorePage {
        let payload = try JSONDecoder().decode(StorePayload.self, from: data)
        return ExtensionStorePage(
            listings: payload.data.compactMap(listing(from:)),
            totalResults: payload.totalResults, rawCount: payload.data.count)
    }

    /// The detail record answers with the entry itself; nil when it can't be downloaded any more.
    static func parseDetail(_ data: Data) throws -> ExtensionStoreDetail? {
        let entry = try JSONDecoder().decode(StoreEntry.self, from: data)
        guard let listing = listing(from: entry) else { return nil }
        return ExtensionStoreDetail(
            listing: listing,
            screenshots: (entry.metadata ?? []).compactMap(URL.init(string:)),
            commands: (entry.commands ?? []).compactMap { command in
                guard let name = command.name else { return nil }
                return ExtensionStoreDetail.Command(
                    name: name, title: command.title ?? name, summary: command.description ?? "")
            },
            changelog: (entry.changelog?.versions ?? []).map {
                ExtensionStoreDetail.Release(
                    title: $0.title ?? "", date: $0.date.flatMap(releaseDate), markdown: $0.markdown ?? "")
            },
            readmeURL: entry.readmeURL.flatMap(readmeRawURL))
    }

    /// The store's `readme_url` is a GitHub page; the body is the same path on the raw host.
    static func readmeRawURL(_ pageURL: String) -> URL? {
        guard let url = URL(string: pageURL), url.host == "github.com" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count > 4, parts[2] == "tree" || parts[2] == "blob" else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "raw.githubusercontent.com"
        components.path = "/" + ([parts[0], parts[1]] + parts[3...]).joined(separator: "/")
        return components.url
    }

    private static func releaseDate(_ text: String) -> Date? {
        try? Date(text, strategy: .iso8601.year().month().day())
    }

    /// A lookup answers with the entry itself, not a page of them.
    static func parseEntry(_ data: Data) throws -> ExtensionListing? {
        listing(from: try JSONDecoder().decode(StoreEntry.self, from: data))
    }

    /// An entry without a usable download is dropped, not listed as uninstallable.
    private static func listing(from entry: StoreEntry) -> ExtensionListing? {
        // A de-listed extension is still returned by search; it can't be downloaded any more.
        guard entry.status == nil || entry.status == "active" else { return nil }
        guard let raw = entry.downloadURL, let url = URL(string: raw) else { return nil }
        return ExtensionListing(
            id: entry.id,
            name: entry.name,
            title: entry.title ?? entry.name,
            summary: entry.description ?? "",
            author: entry.author?.name ?? entry.author?.handle ?? "",
            lightIconURL: entry.icons?.light.flatMap(URL.init(string:)),
            darkIconURL: entry.icons?.dark.flatMap(URL.init(string:)),
            commandCount: entry.commands?.count ?? 0,
            downloadCount: entry.downloadCount,
            downloadURL: url,
            commitSHA: entry.commitSHA,
            categories: entry.categories ?? [],
            updatedAt: entry.updatedAt.map(Date.init(timeIntervalSince1970:)),
            storeURL: entry.storeURL.flatMap(URL.init(string:)))
    }
}

/// One page of the list or of a search.
struct ExtensionStorePage: Sendable {
    let listings: [ExtensionListing]
    let totalResults: Int?
    let rawCount: Int
}

/// What an extension's own page shows beyond its list row.
struct ExtensionStoreDetail: Sendable, Equatable {
    struct Command: Sendable, Equatable, Identifiable {
        let name: String
        let title: String
        let summary: String

        var id: String { name }
    }

    struct Release: Sendable, Equatable {
        let title: String
        /// A day with no time, so it is read and shown in GMT.
        let date: Date?
        let markdown: String
    }

    let listing: ExtensionListing
    let screenshots: [URL]
    let commands: [Command]
    /// Newest first, as the store sends it.
    let changelog: [Release]
    let readmeURL: URL?
}

enum ExtensionStoreError: LocalizedError {
    case malformedResponse
    case rejected(String)
    case downloadFailed(String)
    case noPackageManager
    case noNode
    case buildFailed(String)
    case notAnExtension

    var errorDescription: String? {
        switch self {
        case .malformedResponse:
            return String(localized: "The server answered with something this version doesn't understand.")
        case .rejected(let message):
            return message
        case .downloadFailed(let reason):
            return String(localized: "Download failed: \(reason)")
        case .noPackageManager:
            return String(
                localized: """
                    No package manager was found. Install pnpm, npm, Yarn or Bun, or add the folder it \
                    lives in to Custom search paths.
                    """)
        case .noNode:
            return String(
                localized: """
                    Node wasn't found. Install Node.js, add the folder it lives in to Custom search \
                    paths, or install this extension from the Raycast Store instead.
                    """)
        case .buildFailed(let output):
            return String(localized: "The extension didn't build: \(output)")
        case .notAnExtension:
            return String(localized: "That download didn't contain a Raycast extension.")
        }
    }
}
