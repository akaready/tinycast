import Foundation

/// Everything a card or a row can do with a value.
enum ContactAction: String, Codable, CaseIterable, Sendable {
    case message
    case faceTime
    case call
    case compose
    case openInMaps
    case openInContacts
    case copy
    case copyName
}

/// What a key press is aimed at: one kind of field, or the contact row itself.
enum ContactTarget: String, Codable, CaseIterable, Sendable {
    case phone
    case email
    case address
    case birthday
    case contact

    init(_ kind: ContactField.Kind) {
        switch kind {
        case .phone: self = .phone
        case .email: self = .email
        case .address: self = .address
        case .birthday: self = .birthday
        }
    }

    /// The actions that make sense here, in the order a picker lists them.
    var actions: [ContactAction] {
        switch self {
        case .phone: [.message, .faceTime, .call, .copy]
        case .email: [.compose, .copy]
        case .address: [.openInMaps, .copy]
        case .birthday: [.copy]
        case .contact: [.openInContacts, .copyName]
        }
    }

    func standard(command: Bool) -> ContactAction {
        switch (self, command) {
        case (.phone, false): .message
        case (.email, false): .compose
        case (.address, false): .openInMaps
        case (.contact, false): .openInContacts
        case (.contact, true): .copyName
        default: .copy
        }
    }
}

/// What ↵ and ⌘↵ do for each target; only the differences from the defaults are stored.
struct ContactActionChoices: Codable, Equatable, Sendable {
    private var stored: [String: ContactAction] = [:]

    static let standard = ContactActionChoices()

    var isStandard: Bool { stored.isEmpty }

    /// A stored choice the target no longer offers falls back to the default.
    func action(for target: ContactTarget, command: Bool) -> ContactAction {
        if let chosen = stored[Self.key(target, command)], target.actions.contains(chosen) {
            return chosen
        }
        return target.standard(command: command)
    }

    mutating func set(_ action: ContactAction, for target: ContactTarget, command: Bool) {
        guard target.actions.contains(action) else { return }
        let key = Self.key(target, command)
        if action == target.standard(command: command) {
            stored[key] = nil
        } else {
            stored[key] = action
        }
    }

    private static func key(_ target: ContactTarget, _ command: Bool) -> String {
        target.rawValue + (command ? ".command" : ".return")
    }

    var json: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// Anything unreadable is the defaults, never a failure.
    init(json: String?) {
        self = json.flatMap { try? JSONDecoder().decode(Self.self, from: Data($0.utf8)) } ?? .standard
    }

    init() {}
}

/// The apps that can be asked to handle a hand-off; each otherwise goes to the system default.
enum ContactAppRole: String, Codable, CaseIterable, Sendable {
    case mail
    case messages
    case maps
}

/// An app picked by the user: the bundle identifier finds it, the path is the fallback and the label.
struct ContactAppChoice: Codable, Equatable, Sendable {
    let bundleID: String
    let path: String
}

struct ContactAppChoices: Codable, Equatable, Sendable {
    private var stored: [String: ContactAppChoice] = [:]

    subscript(role: ContactAppRole) -> ContactAppChoice? {
        get { stored[role.rawValue] }
        set { stored[role.rawValue] = newValue }
    }

    var json: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    init(json: String?) {
        self = json.flatMap { try? JSONDecoder().decode(Self.self, from: Data($0.utf8)) } ?? Self()
    }

    init() {}
}
