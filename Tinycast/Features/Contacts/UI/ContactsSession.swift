import Foundation

/// The open Contacts screen's list: it exists only while the screen is up, so no card outlives it.
@MainActor
@Observable
final class ContactsSession {
    enum Phase {
        case loading
        case loaded
    }

    private(set) var contacts: [Contact] = []
    private(set) var phase: Phase = .loading
    private(set) var query = ""
    let store: ContactStore
    /// Where the keyboard is: the results list, or one of the selected card's stops.
    private(set) var focus = ContactCardFocus()
    /// The field whose value was just copied, shown as "Copied" until the feedback runs out.
    private(set) var copiedID: String?
    private(set) var photos: [String: Data] = [:]
    /// Rows arrive as names only; a card's addresses and birthday and a row's thumbnail fill in after.
    private(set) var details: [String: Contact] = [:]
    private(set) var thumbnails: [String: Data] = [:]

    @ObservationIgnored private var loading: Task<Void, Never>?
    /// Bumped per fetch, so an answer to an older query can tell it is no longer wanted.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var copyReset: Task<Void, Never>?
    /// The browse list, kept between opens so the screen appears at once; names only, no photos.
    @ObservationIgnored private var browseCache: [Contact]?
    @ObservationIgnored private var isObserving = false

    /// A few cards at a time: the photos are full size, and only the open card needs one.
    private static let photoCacheLimit = 8

    init(store: ContactStore) {
        self.store = store
    }

    func start(query raw: String) {
        isRunning = true
        query = ContactQuery.normalized(raw)
        store.refreshAccess()
        guard store.access == .granted else {
            purge()
            reload()
            return
        }
        observeOnce()
        if query.isEmpty, let browseCache {
            contacts = browseCache
            phase = .loaded
            return
        }
        reload()
    }

    /// Drops the warm list and stops watching; used when the feature goes off or access is gone.
    func purge() {
        browseCache = nil
        store.stopObserving()
        isObserving = false
    }

    /// Stays registered after `end` while a warm list exists, so an edit elsewhere still discards it.
    private func observeOnce() {
        guard !isObserving else { return }
        isObserving = true
        store.observeChanges { [weak self] in
            guard let self else { return }
            browseCache = nil
            if isRunning { reload() }
        }
    }

    func setQuery(_ raw: String) {
        let next = ContactQuery.normalized(raw)
        guard next != query else { return }
        focus.leave()
        query = next
        reload()
    }

    func end() {
        isRunning = false
        generation += 1
        loading?.cancel()
        loading = nil
        copyReset?.cancel()
        copiedID = nil
        focus.leave()
        photos = [:]
        details = [:]
        thumbnails = [:]
        contacts = []
        phase = .loading
    }

    func updateFocus(_ change: (inout ContactCardFocus) -> Void) {
        var next = focus
        change(&next)
        if next != focus { focus = next }
    }

    /// A row's contact with whatever has been read since: the list holds only the light keys.
    func resolved(_ contact: Contact) -> Contact { details[contact.id] ?? contact }

    func loadDetail(for id: String) async {
        guard isRunning, details[id] == nil else { return }
        guard let card = await store.card(for: id), isRunning else { return }
        details[id] = card
    }

    func loadThumbnail(for id: String) async {
        guard isRunning, thumbnails[id] == nil else { return }
        guard let data = await store.thumbnail(for: id), isRunning else { return }
        thumbnails[id] = data
    }

    func photo(for id: String, maxPixel: Int) async {
        guard isRunning, photos[id] == nil else { return }
        guard let data = await store.photo(for: id, maxPixel: maxPixel), isRunning else { return }
        if photos.count >= Self.photoCacheLimit { photos = [:] }
        photos[id] = data
    }

    func flashCopied(_ id: String) {
        copiedID = id
        copyReset?.cancel()
        copyReset = Task {
            try? await Task.sleep(for: .seconds(Theme.Duration.copyFeedback))
            guard !Task.isCancelled else { return }
            copiedID = nil
        }
    }

    private func reload() {
        guard isRunning, store.access == .granted else {
            contacts = []
            phase = .loaded
            return
        }
        loading?.cancel()
        generation += 1
        let mine = generation
        let asked = query
        loading = Task {
            let found = await store.contacts(matching: asked)
            guard mine == generation, !Task.isCancelled else { return }
            contacts = found
            if asked.isEmpty { browseCache = found }
            phase = .loaded
        }
    }
}
