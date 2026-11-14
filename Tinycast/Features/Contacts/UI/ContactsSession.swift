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

    @ObservationIgnored private var loading: Task<Void, Never>?
    /// Bumped per fetch, so an answer to an older query can tell it is no longer wanted.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isRunning = false

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
        query = next
        reload()
    }

    func end() {
        isRunning = false
        generation += 1
        loading?.cancel()
        loading = nil
        store.stopObserving()
        contacts = []
        phase = .loading
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
