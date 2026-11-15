import Foundation

/// What Space does straight after a query that is exactly an entry's alias: engage it, or type a space.
enum AliasEngage {
    enum Action: Equatable, Sendable {
        /// The entry opens a screen, so Space enters it as ↵ would.
        case open
        /// The entry asks for typed values, so Space moves into its first field.
        case focusArguments
    }

    /// An entry that takes no further input yields nil: Space never launches an app or runs a command.
    static func action(
        enabled: Bool, query: String, alias: String?, hasArgumentFields: Bool, opensScreen: Bool,
        isComposing: Bool, menuOpen: Bool, controlListOpen: Bool
    ) -> Action? {
        guard enabled, !isComposing, !menuOpen, !controlListOpen, let alias, matches(query, alias: alias)
        else { return nil }
        if hasArgumentFields { return .focusArguments }
        return opensScreen ? .open : nil
    }

    /// The whole query, so any text after the alias keeps Space an ordinary space.
    static func matches(_ query: String, alias: String) -> Bool {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && query.caseInsensitiveCompare(trimmed) == .orderedSame
    }
}
