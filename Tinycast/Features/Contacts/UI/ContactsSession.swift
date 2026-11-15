import Foundation

/// The Contacts index and the open screen's state; photos and card details live only while it is up.
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
    @ObservationIgnored private var debounce: Task<Void, Never>?
    /// Bumped on every load and purge, so a load that finishes after either can tell it is unwanted.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var isObserving = false
    @ObservationIgnored private var copyReset: Task<Void, Never>?
    /// Everyone, names only: filtered in memory per keystroke, rebuilt when the address book changes.
    @ObservationIgnored private var index: ContactIndex?

    /// A few cards at a time: the photos are full size, and only the open card needs one.
    private static let photoCacheLimit = 8
    private static let thumbnailCacheLimit = 300
    /// Edits arrive in bursts (a sync can touch hundreds of cards), so the reload waits them out.
    private static let reloadDelay: Duration = .milliseconds(600)

    init(store: ContactStore) {
        self.store = store
    }

    /// Builds the index in the background; called at launch and after a grant, so the screen is ready.
    func warm() {
        store.refreshAccess()
        guard store.access == .granted else {
            purge()
            return
        }
        observeOnce()
        if index == nil { load() }
    }

    func start(query raw: String) {
        isRunning = true
        query = ContactQuery.normalized(raw)
        warm()
        refresh()
    }

    func setQuery(_ raw: String) {
        let next = ContactQuery.normalized(raw)
        guard next != query else { return }
        focus.leave()
        query = next
        refresh()
    }

    func end() {
        isRunning = false
        copyReset?.cancel()
        copiedID = nil
        focus.leave()
        photos = [:]
        details = [:]
        thumbnails = [:]
        contacts = []
        phase = .loading
    }

    /// Drops the index and stops watching: the feature is off, or access is gone.
    func purge() {
        generation += 1
        loading?.cancel()
        loading = nil
        debounce?.cancel()
        debounce = nil
        index = nil
        store.stopObserving()
        isObserving = false
        contacts = []
        phase = .loaded
    }

    private func observeOnce() {
        guard !isObserving else { return }
        isObserving = true
        store.observeChanges { [weak self] in self?.scheduleReload() }
    }

    private func scheduleReload() {
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: Self.reloadDelay)
            guard !Task.isCancelled else { return }
            loading?.cancel()
            loading = nil
            load()
        }
    }

    private func load() {
        guard loading == nil else { return }
        generation += 1
        let mine = generation
        loading = Task {
            let found = await store.allContacts()
            guard mine == generation, !Task.isCancelled else { return }
            loading = nil
            index = ContactIndex(found)
            if isRunning { refresh() }
        }
    }

    private func refresh() {
        guard isRunning else { return }
        if let index {
            contacts = index.matching(query)
            phase = .loaded
        } else {
            contacts = []
            phase = store.access == .granted ? .loading : .loaded
        }
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
        if thumbnails.count >= Self.thumbnailCacheLimit { thumbnails = [:] }
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
}
