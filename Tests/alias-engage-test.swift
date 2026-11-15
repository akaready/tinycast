import Foundation

@main
struct AliasEngageTest {
    static func main() {
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        func action(
            enabled: Bool = true, query: String = "c", alias: String? = "c",
            fields: Bool = false, opens: Bool = false, composing: Bool = false,
            menu: Bool = false, controls: Bool = false
        ) -> AliasEngage.Action? {
            AliasEngage.action(
                enabled: enabled, query: query, alias: alias, hasArgumentFields: fields,
                opensScreen: opens, isComposing: composing, menuOpen: menu, controlListOpen: controls)
        }

        check("a screen command opens on an exact alias", action(opens: true) == .open)
        check("argument fields take focus", action(fields: true) == .focusArguments)
        check("fields win over opening a screen", action(fields: true, opens: true) == .focusArguments)
        check("an entry with no further input is left alone", action() == nil)
        check("off by default means nothing engages", action(enabled: false, opens: true) == nil)
        check("case is ignored", action(query: "C", alias: "c", opens: true) == .open)
        check("case is ignored in the alias", action(query: "ct", alias: "CT", opens: true) == .open)
        check("a prefix of the alias does not engage", action(query: "t", alias: "tog", opens: true) == nil)
        check(
            "an alias that is a prefix of the query does not engage",
            action(query: "co", alias: "c", opens: true) == nil)
        check("extra text after the alias does not engage", action(query: "c x", opens: true) == nil)
        check("a trailing space is other text", action(query: "c ", opens: true) == nil)
        check("an empty query never engages", action(query: "", alias: "", opens: true) == nil)
        check("an entry with no alias never engages", action(alias: nil, opens: true) == nil)
        check("a blank alias never engages", action(query: " ", alias: "  ", opens: true) == nil)
        check(
            "an alias typed with stray spaces still matches",
            action(query: "c", alias: " c ", opens: true) == .open)
        check(
            "a multi-word alias needs the whole phrase",
            action(query: "toggle", alias: "toggle dark", opens: true) == nil)
        check("composing text blocks it", action(opens: true, composing: true) == nil)
        check("an open menu blocks it", action(opens: true, menu: true) == nil)
        check("an open control list blocks it", action(fields: true, controls: true) == nil)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
