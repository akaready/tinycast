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

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            passes += 1
        } else {
            print("FAIL: \(label)")
            failures += 1
        }
    }
}
