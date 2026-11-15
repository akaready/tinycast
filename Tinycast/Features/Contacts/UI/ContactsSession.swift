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

    @ObservationIgnored private var loading: Task<Void, Never>?
    /// Bumped per fetch, so an answer to an older query can tell it is no longer wanted.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var copyReset: Task<Void, Never>?

    /// A few cards at a time: the photos are full size, and only the open card needs one.
    private static let photoCacheLimit = 8

    init(store: ContactStore) {
        self.store = store
    }

    func start(query raw: String) {
        isRunning = true
        query = ContactQuery.normalized(raw)
        store.refreshAccess()
        store.observeChanges { [weak self] in self?.reload() }
        reload()
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
        store.stopObserving()
        copyReset?.cancel()
        copiedID = nil
        focus.leave()
        photos = [:]
        contacts = []
        phase = .loading
    }

    func updateFocus(_ change: (inout ContactCardFocus) -> Void) {
        var next = focus
        change(&next)
        if next != focus { focus = next }
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
            phase = .loaded
        }
    }
}
