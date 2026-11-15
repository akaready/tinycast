import Foundation

@main
@MainActor
struct ContactsTests {
    static var failures = 0
    static var passes = 0

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    static let locale = Locale(identifier: "en_US")

    static func main() {
        queryNormalisation()
        labels()
        dialing()
        urls()
        addressLines()
        birthdays()
        naming()
        ordering()
        mapsLinks()
        cardLayout()
        cardFocus()
        monogram()
        indexFilter()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func queryNormalisation() {
        expect(ContactQuery.normalized("  ada   lovelace ") == "ada lovelace", "inner runs collapse")
        expect(ContactQuery.normalized("\tada\n") == "ada", "tabs and newlines trim")
        expect(ContactQuery.normalized("   ").isEmpty, "blank is the browse query")
        expect(ContactQuery.normalized("") == "", "empty stays empty")
    }

    static func labels() {
        expect(ContactFormat.label("mobile") == "Mobile", "first letter is capitalised")
        expect(ContactFormat.label("") == "", "no label stays empty")
        expect(ContactFormat.label("iPhone") == "IPhone", "only the first letter changes")
    }

    static func dialing() {
        expect(ContactFormat.dialable("(555) 123-4567") == "5551234567", "punctuation drops")
        expect(ContactFormat.dialable("+1 555 123 4567") == "+15551234567", "a leading plus stays")
        expect(ContactFormat.dialable(" +44 20 7946 0958") == "+442079460958", "leading space is ignored")
        expect(ContactFormat.dialable("555-1234 ext 9") == "55512349", "letters drop")
    }

    static func urls() {
        expect(ContactFormat.callURL("(555) 123-4567")?.absoluteString == "tel:5551234567", "call")
        expect(ContactFormat.messageURL("+1 555 1234")?.absoluteString == "sms:+15551234", "message")
        expect(
            ContactFormat.faceTimeURL("555 1234")?.absoluteString == "facetime:5551234", "facetime")
        expect(ContactFormat.callURL("ext") == nil, "a value with no digits has no URL")
        expect(
            ContactFormat.mailURL("ada@example.com")?.absoluteString == "mailto:ada@example.com",
            "mail")
        expect(
            ContactFormat.mailURL("a b@example.com")?.absoluteString == "mailto:a%20b@example.com",
            "mail escapes spaces")
        expect(ContactFormat.mailURL("") == nil, "no address, no URL")
        expect(
            ContactFormat.contactsURL(id: "ABC-123:ABPerson")?.absoluteString
                == "addressbook://ABC-123:ABPerson",
            "contacts url keeps the identifier")
    }

    static func addressLines() {
        expect(
            ContactFormat.oneLine("1 Main St\nSpringfield IL 62701\nUSA")
                == "1 Main St, Springfield IL 62701, USA",
            "lines join with commas")
        expect(ContactFormat.oneLine("1 Main St\n\n  \nUSA") == "1 Main St, USA", "blank lines drop")
        expect(ContactFormat.oneLine("") == "", "empty stays empty")
    }

    static func birthdays() {
        let noYear = DateComponents(month: 3, day: 3)
        let withYear = DateComponents(year: 1990, month: 3, day: 3)
        expect(
            ContactFormat.birthday(noYear, calendar: calendar, locale: locale) == "March 3",
            "no year shows month and day")
        expect(
            ContactFormat.birthday(withYear, calendar: calendar, locale: locale) == "March 3, 1990",
            "a known year is shown")
        expect(
            ContactFormat.birthday(DateComponents(month: 2, day: 29), calendar: calendar, locale: locale)
                == "February 29",
            "a leap day survives without a year")
        expect(
            ContactFormat.birthday(DateComponents(year: 1990), calendar: calendar, locale: locale) == nil,
            "a date with no month or day is nothing")
    }

    static func naming() {
        let person = Contact(id: "1", givenName: "Ada", familyName: "Lovelace")
        expect(person.displayName == "Ada Lovelace", "given and family")
        expect(Contact(id: "2", givenName: "Ada").displayName == "Ada", "given alone")
        expect(Contact(id: "3", organization: "Acme").displayName == "Acme", "company card")
        expect(Contact(id: "4", nickname: "Bee", organization: "Acme").displayName == "Bee", "nickname first")
        let mail = Contact.Entry(id: "e", label: "", value: "x@example.com")
        expect(Contact(id: "5", emails: [mail]).displayName == "x@example.com", "falls back to email")
        expect(!Contact(id: "6").displayName.isEmpty, "a blank card still has a name")

        expect(person.initials == "AL", "two initials")
        expect(Contact(id: "7", organization: "acme").initials == "A", "company initial")

        let job = Contact(id: "8", givenName: "Ada", organization: "Acme", jobTitle: "Analyst")
        expect(job.subtitle == "Analyst · Acme", "role and company")
        expect(Contact(id: "9", organization: "Acme").subtitle.isEmpty, "a company card repeats nothing")
        expect(Contact(id: "10", givenName: "Ada").subtitle.isEmpty, "no role, no subtitle")
        expect(Contact(id: "11").isEmpty, "a card with no values is empty")
        expect(!Contact(id: "12", emails: [mail]).isEmpty, "an email is a value")
    }

    static func ordering() {
        let sorted = Contact.sorted([
            Contact(id: "4", givenName: "Zed"),
            Contact(id: "3", givenName: "bea"),
            Contact(id: "2", givenName: "Ada"),
            Contact(id: "1", givenName: "Ada")
        ])
        expect(sorted.map(\.id) == ["1", "2", "3", "4"], "alphabetical, ties by id")
    }

    static func mapsLinks() {
        expect(
            ContactFormat.mapsURL("1 Main St\nSpringfield IL")?.absoluteString
                == "maps://?q=1%20Main%20St,%20Springfield%20IL",
            "maps searches the one-line address")
        expect(
            ContactFormat.mapsURL("A&B Co\n5 Rd")?.absoluteString == "maps://?q=A%26B%20Co,%205%20Rd",
            "an ampersand cannot end the query")
        expect(ContactFormat.mapsURL(" \n ") == nil, "a blank address has no URL")
    }

    static let fullCard = Contact(
        id: "c", givenName: "Ada", familyName: "Lovelace",
        phones: [
            Contact.Entry(id: "p1", label: "Mobile", value: "555 1234"),
            Contact.Entry(id: "p2", label: "Work", value: "555 9999")
        ],
        emails: [Contact.Entry(id: "e1", label: "Home", value: "ada@example.com")],
        addresses: [Contact.Entry(id: "a1", label: "Home", value: "1 Main St\nSpringfield")],
        birthday: DateComponents(month: 12, day: 10))

    static func cardLayout() {
        let card = ContactCard(fullCard, calendar: calendar, locale: locale)
        expect(
            card.fields.map(\.id) == ["p1", "p2", "e1", "a1", "birthday"],
            "phones, emails, addresses, then the birthday")
        expect(card.fields.last?.value == "December 10", "the birthday is formatted")
        expect(card.quickActions == [.message, .faceTime, .email], "a number and an email give three")
        expect(card.stopCount == 6, "the quick row is one stop before the five fields")
        expect(card.field(atStop: 0) == nil, "stop 0 is the quick row")
        expect(card.field(atStop: 1)?.id == "p1", "stop 1 is the first field")
        expect(card.stop(of: card.fields[2]) == 3, "a field knows its stop")

        let phoneOnly = ContactCard(
            Contact(id: "d", phones: [Contact.Entry(id: "p", label: "", value: "1")]),
            calendar: calendar, locale: locale)
        expect(phoneOnly.quickActions == [.message, .faceTime], "no email, no email button")
        let bare = ContactCard(Contact(id: "e", givenName: "Bo"), calendar: calendar, locale: locale)
        expect(!bare.hasQuickRow && bare.stopCount == 0, "a card with nothing has no stops")
        expect(bare.fields.isEmpty, "empty sections are omitted")
        let year = ContactCard(
            Contact(id: "f", birthday: DateComponents(year: 1990)), calendar: calendar, locale: locale)
        expect(year.fields.isEmpty, "a part-empty birthday is not a field")
    }

    static func cardFocus() {
        var focus = ContactCardFocus()
        expect(!focus.isInCard, "focus starts in the list")
        expect(!focus.enter(stops: 0), "an empty card cannot be entered")
        expect(focus.enter(stops: 3) && focus.stop == 0, "entering lands on the first stop")
        focus.moveVertically(1, stops: 3)
        focus.moveVertically(1, stops: 3)
        focus.moveVertically(1, stops: 3)
        expect(focus.stop == 2, "down clamps at the last stop")
        focus.moveVertically(-5, stops: 3)
        expect(focus.stop == 0, "up clamps at the first stop")

        focus.moveHorizontally(1, onQuickRow: true, buttons: 3)
        focus.moveHorizontally(1, onQuickRow: true, buttons: 3)
        focus.moveHorizontally(1, onQuickRow: true, buttons: 3)
        expect(focus.button == 2, "right stops on the last quick action")
        focus.moveHorizontally(-1, onQuickRow: true, buttons: 3)
        expect(focus.button == 1 && focus.isInCard, "left steps back inside the row")
        focus.moveVertically(1, stops: 3)
        expect(focus.button == 0, "a new stop resets the button")

        focus.moveHorizontally(1, onQuickRow: false, buttons: 3)
        expect(focus.isInCard, "right on a field does nothing")
        focus.moveHorizontally(-1, onQuickRow: false, buttons: 3)
        expect(!focus.isInCard, "left on a field returns to the list")

        focus.enter(stops: 3)
        focus.moveHorizontally(-1, onQuickRow: true, buttons: 3)
        expect(!focus.isInCard, "left on the first quick action returns to the list")

        focus.enter(stops: 2)
        focus.tab(backwards: false, stops: 2)
        expect(focus.stop == 1, "tab advances")
        focus.tab(backwards: false, stops: 2)
        expect(!focus.isInCard, "tab past the last stop returns to the list")
        focus.enter(stops: 2)
        focus.tab(backwards: true, stops: 2)
        expect(!focus.isInCard, "shift-tab before the first stop returns to the list")

        focus.focus(stop: 9, stops: 2)
        expect(!focus.isInCard, "a stop that does not exist is ignored")
        focus.focus(stop: 1, stops: 2)
        expect(focus.stop == 1, "a click focuses its stop")
    }

    static func monogram() {
        expect(
            ContactMonogram.hue(for: "Ada Lovelace") == ContactMonogram.hue(for: "Ada Lovelace"),
            "the hue is stable")
        expect(
            ContactMonogram.hue(for: "ada lovelace") == ContactMonogram.hue(for: "Ada Lovelace"),
            "case does not change the hue")
        expect(
            ContactMonogram.hue(for: "Ada") != ContactMonogram.hue(for: "Grace"), "names differ")
        let hues = ["", "A", "Zed", "Ünïcode 名前", String(repeating: "x", count: 500)]
            .map(ContactMonogram.hue(for:))
        expect(hues.allSatisfy { $0 >= 0 && $0 < 1 }, "hue stays in 0..<1")
        expect(
            fullCard.monogramHue == ContactMonogram.hue(for: "Ada Lovelace"),
            "a card's hue follows its display name")
    }

    static func indexFilter() {
        let people = [
            Contact(
                id: "1", givenName: "Zoë", familyName: "Åberg", organization: "Acme Corp",
                phones: [Contact.Entry(id: "p", label: "", value: "+1 (555) 123-4567")]),
            Contact(
                id: "2", givenName: "Ada", familyName: "Lovelace", nickname: "Countess",
                organization: "Analytical Engines",
                emails: [Contact.Entry(id: "e", label: "", value: "ada@Babbage.example")]),
            Contact(id: "3", givenName: "Adam", familyName: "Zed", organization: "Ada Labs"),
            Contact(id: "4", givenName: "Bob", familyName: "Mac", jobTitle: "Engineer")
        ]
        let index = ContactIndex(people)
        func ids(_ query: String) -> [String] { index.matching(query).map(\.id) }

        expect(index.count == 4 && ids("").count == 4, "an empty query is everyone, in order")
        expect(ids("   ") == ["1", "2", "3", "4"], "a blank query is everyone")
        expect(ids("zoe") == ["1"], "diacritics fold")
        expect(ids("ÅBERG") == ["1"], "case and diacritics fold on both sides")
        expect(ids("lovel") == ["2"], "a family-name prefix matches")
        expect(ids("count") == ["2"], "the nickname matches")
        expect(ids("ada") == ["2", "3"], "name prefixes outrank a company-only match, ties keep order")
        expect(ids("ada zed") == ["3"], "every word must match")
        expect(ids("lace") == ["2"], "a substring of a name matches")
        expect(ids("acme") == ["1"], "the company matches")
        expect(ids("engine") == ["2", "4"], "company words outrank job-title substrings only by prefix")
        expect(ids("babbage") == ["2"], "an email matches case-insensitively")
        expect(ids("5551234") == ["1"], "phone digits match through punctuation")
        expect(ids("+1 555") == ["1"], "a plus and spaces still match a number")
        expect(ids("zzz").isEmpty, "no match is empty")
        expect(ids("a-b") .isEmpty, "a word absent from every card finds nothing")
    }

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            passes += 1
        } else {
            print("FAIL: \(label)")
            failures += 1
        }
    }
}
