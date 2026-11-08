import Foundation
import Observation

/// What the Store screen shows and the requests behind it; one lives while the screen is open.
@Observable @MainActor
final class ExtensionStoreSession {
    enum Filter: CaseIterable {
        case all, installed, updates

        var title: String {
            switch self {
            case .all: return String(localized: "All")
            case .installed: return String(localized: "Installed")
            case .updates: return String(localized: "Updates")
            }
        }

        var systemImage: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .installed: return "checkmark.circle"
            case .updates: return "arrow.triangle.2.circlepath"
            }
        }
    }

    enum ListPhase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum Fetch<Value: Equatable & Sendable>: Equatable {
        case loading
        case loaded(Value)
        /// The store has no page for it: de-listed, or never published there.
        case unavailable
        case failed(String)
    }

    enum InstallState: Equatable {
        case available
        case installing(String)
        case installed
        case updateAvailable
        case updating
    }

    /// A store listing, an installed extension, or both: Installed lists what is on disk.
    struct Entry: Identifiable, Equatable {
        let listing: ExtensionListing?
        let installed: InstalledExtension?

        var id: String { listing?.name ?? installed?.manifest.name ?? "" }
        var title: String { listing?.title ?? installed?.title ?? id }
        var author: String { listing?.author ?? installed?.manifest.author ?? "" }
        var summary: String { listing?.summary ?? installed?.manifest.description ?? "" }
        var downloadCount: Int? { listing?.downloadCount }
        var handle: String? { listing?.storeHandle ?? installed?.manifest.storeHandle }
        var key: String { "\(handle ?? "")/\(id)" }

        var pageURL: URL? {
            if let url = listing?.storeURL { return url }
            guard let handle else { return nil }
            return URL(string: "https://www.raycast.com")?.appending(path: handle).appending(path: id)
        }
    }

    private static let debounce = Duration.milliseconds(350)
    private static let selectionSettle = Duration.milliseconds(200)
    private static let pageLookahead = 3
    private static let cachedPages = 20

    private(set) var query = ""
    private(set) var filter = Filter.all
    private(set) var listings: [ExtensionListing] = []
    private(set) var phase = ListPhase.idle
    private(set) var isLoadingMore = false
    private(set) var selected: Entry?
    private(set) var details: [String: Fetch<ExtensionStoreDetail>] = [:]
    private(set) var readmes: [String: Fetch<String>] = [:]
    private(set) var installing: [String: String] = [:]
    private(set) var failures: [String: String] = [:]

    @ObservationIgnored private let extensions: ExtensionManager
    @ObservationIgnored private let client: ExtensionStoreClient
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var nextPage = 1
    @ObservationIgnored private var fetched = 0
    @ObservationIgnored private var hasMore = false
    @ObservationIgnored private var moreFailed = false
    @ObservationIgnored private var pagesQuery = ""
    @ObservationIgnored private var cacheOrder: [String] = []
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var pageTask: Task<Void, Never>?
    @ObservationIgnored private var detailTask: Task<Void, Never>?
    @ObservationIgnored private var updateTask: Task<Void, Never>?

    init(extensions: ExtensionManager, client: ExtensionStoreClient = ExtensionStoreClient()) {
        self.extensions = extensions
        self.client = client
    }

    // MARK: - Lifetime

    /// Idempotent; the screen calls it on appear.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        updateTask = Task { [extensions] in await extensions.checkForUpdates() }
        reload()
    }

    /// Drops everything fetched, so the memory goes back with the palette.
    func end() {
        isRunning = false
        generation += 1
        [searchTask, pageTask, detailTask, updateTask].forEach { $0?.cancel() }
        (searchTask, pageTask, detailTask, updateTask) = (nil, nil, nil, nil)
        query = ""
        filter = .all
        listings = []
        phase = .idle
        isLoadingMore = false
        selected = nil
        details = [:]
        readmes = [:]
        failures = [:]
        cacheOrder = []
    }

    // MARK: - Rows

    var entries: [Entry] {
        switch filter {
        case .all:
            return listings.map { Entry(listing: $0, installed: nil) }
        case .installed:
            let known = Dictionary(listings.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
                .merging(extensions.updates) { _, update in update }
            return extensions.installed
                .map { Entry(listing: known[$0.manifest.name], installed: $0) }
                .filter(matchesQuery).sorted(by: Self.byTitle)
        case .updates:
            return extensions.updates.values
                .map { Entry(listing: $0, installed: extensions.extensionNamed($0.name)) }
                .filter(matchesQuery).sorted(by: Self.byTitle)
        }
    }

    private static func byTitle(_ lhs: Entry, _ rhs: Entry) -> Bool {
        lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private func matchesQuery(_ entry: Entry) -> Bool {
        query.isEmpty
            || [entry.title, entry.author, entry.summary].contains { $0.localizedStandardContains(query) }
    }

    func state(for entry: Entry) -> InstallState {
        if let message = installing[entry.id] { return .installing(message) }
        if extensions.updating.contains(entry.id) { return .updating }
        guard extensions.extensionNamed(entry.id) != nil else { return .available }
        return extensions.updates[entry.id] == nil ? .installed : .updateAvailable
    }

    func installedExtension(for entry: Entry) -> InstalledExtension? {
        extensions.extensionNamed(entry.id)
    }

    // MARK: - Query and paging

    func setQuery(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed != query else { return }
        query = trimmed
        if filter == .all { scheduleReload() }
    }

    func setFilter(_ next: Filter) {
        guard next != filter else { return }
        filter = next
        if next == .all, pagesQuery != query { scheduleReload() }
    }

    /// Called with the highlighted or an appearing row, so a page loads as the list nears its end.
    func loadNextPageIfNeeded(nearIndex: Int) {
        guard filter == .all, phase == .loaded, hasMore, !isLoadingMore, !moreFailed,
            nearIndex >= listings.count - Self.pageLookahead
        else { return }
        isLoadingMore = true
        let (query, token, page) = (pagesQuery, generation, nextPage)
        pageTask = Task { await loadPage(page, query: query, token: token) }
    }

    func retry() {
        if case .failed = phase {
            reload()
            return
        }
        moreFailed = false
        guard let selected else { return }
        var failedAny = false
        if case .failed? = details[selected.key] {
            details[selected.key] = nil
            failedAny = true
        }
        if case .failed? = readmes[selected.key] {
            readmes[selected.key] = nil
            failedAny = true
        }
        guard failedAny else { return }
        detailTask?.cancel()
        load(selected)
    }

    private func scheduleReload() {
        guard isRunning else { return }
        searchTask?.cancel()
        pageTask?.cancel()
        generation += 1
        guard !query.isEmpty else {
            reload()
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            reload()
        }
    }

    private func reload() {
        guard isRunning else { return }
        pageTask?.cancel()
        generation += 1
        (nextPage, fetched, hasMore, moreFailed, isLoadingMore) = (1, 0, false, false, false)
        pagesQuery = query
        phase = .loading
        let (query, token) = (query, generation)
        pageTask = Task { await loadPage(1, query: query, token: token) }
    }

    private func isCurrent(_ token: Int) -> Bool {
        !Task.isCancelled && isRunning && token == generation
    }

    private func loadPage(_ page: Int, query: String, token: Int) async {
        do {
            let result =
                query.isEmpty
                ? try await client.browse(page: page)
                : try await client.searchPage(query, page: page)
            guard isCurrent(token) else { return }
            let known = Set(page == 1 ? [] : listings.map(\.name))
            let fresh = result.listings.filter { !known.contains($0.name) }
            listings = page == 1 ? fresh : listings + fresh
            fetched += result.rawCount
            nextPage = page + 1
            hasMore = result.rawCount > 0 && fetched < (result.totalResults ?? .max)
            phase = .loaded
        } catch {
            guard isCurrent(token) else { return }
            if page == 1 {
                listings = []
                phase = .failed(error.localizedDescription)
            } else {
                moreFailed = true
            }
        }
        isLoadingMore = false
    }

    // MARK: - Selection

    func select(_ entry: Entry?) {
        guard entry != selected else { return }
        selected = entry
        detailTask?.cancel()
        detailTask = nil
        if let entry { load(entry) }
    }

    private func load(_ entry: Entry) {
        guard isRunning, let handle = entry.handle else { return }
        detailTask = Task { await loadDetail(of: entry, handle: handle) }
    }

    private func isCurrent(_ entry: Entry) -> Bool {
        !Task.isCancelled && isRunning && selected?.id == entry.id
    }

    private func loadDetail(of entry: Entry, handle: String) async {
        let key = entry.key
        if details[key] == nil {
            // Arrowing through the list passes rows by; only one that stays is looked up.
            try? await Task.sleep(for: Self.selectionSettle)
            guard isCurrent(entry) else { return }
            remember(key)
            details[key] = .loading
            do {
                let detail = try await client.detail(handle: handle, name: entry.id)
                guard isCurrent(entry) else { return forgetLoading(key) }
                details[key] = detail.map { .loaded($0) } ?? .unavailable
            } catch {
                guard isCurrent(entry) else { return forgetLoading(key) }
                // An install from a folder or GitHub has no store page to find.
                details[key] = entry.listing == nil ? .unavailable : .failed(error.localizedDescription)
            }
        }
        guard case .loaded(let detail)? = details[key], readmes[key] == nil else { return }
        guard let url = detail.readmeURL else {
            readmes[key] = .unavailable
            return
        }
        readmes[key] = .loading
        do {
            let text = try await client.readme(url: url)
            guard isCurrent(entry) else { return forgetLoading(key) }
            readmes[key] = .loaded(text)
        } catch {
            guard isCurrent(entry) else { return forgetLoading(key) }
            readmes[key] = .failed(error.localizedDescription)
        }
    }

    /// A cancelled request leaves no `.loading` behind, or the row would never be asked again.
    private func forgetLoading(_ key: String) {
        if details[key] == .loading { details[key] = nil }
        if readmes[key] == .loading { readmes[key] = nil }
    }

    private func remember(_ key: String) {
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        while cacheOrder.count > Self.cachedPages {
            let evicted = cacheOrder.removeFirst()
            details[evicted] = nil
            readmes[evicted] = nil
        }
    }

    // MARK: - Installing

    func install(_ entry: Entry) {
        guard let listing = entry.listing, installing[entry.id] == nil else { return }
        let id = entry.id
        failures[id] = nil
        installing[id] = ExtensionInstaller.Progress.downloading.message
        Task {
            do {
                try await extensions.install(
                    listing,
                    onProgress: { progress in
                        Task { @MainActor in
                            if self.installing[id] != nil { self.installing[id] = progress.message }
                        }
                    })
            } catch {
                failures[id] = error.localizedDescription
            }
            installing[id] = nil
        }
    }

    func update(_ entry: Entry) {
        let id = entry.id
        guard extensions.updates[id] != nil, !extensions.updating.contains(id) else { return }
        failures[id] = nil
        Task {
            let failed = await extensions.update([id])
            if !failed.isEmpty { failures[id] = String(localized: "The update didn't install.") }
        }
    }
}
