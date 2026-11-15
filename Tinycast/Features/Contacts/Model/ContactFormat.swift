import Foundation

/// Display text and the URLs that act on a card's values; nothing here touches the system.
enum ContactFormat {
    /// The system hands back a lower-case label ("mobile"); a row reads better capitalised.
    static func label(_ raw: String) -> String {
        guard let first = raw.first else { return "" }
        return first.uppercased() + raw.dropFirst()
    }

    /// Digits and a leading plus: what a `tel:` URL and FaceTime accept, minus the punctuation.
    static func dialable(_ phone: String) -> String {
        let digits = phone.filter(\.isASCII).filter(\.isNumber)
        return phone.trimmingCharacters(in: .whitespaces).hasPrefix("+") ? "+" + digits : digits
    }

    static func callURL(_ phone: String) -> URL? { dialURL("tel", phone) }
    static func messageURL(_ phone: String) -> URL? { dialURL("sms", phone) }
    static func faceTimeURL(_ phone: String) -> URL? { dialURL("facetime", phone) }

    static func mailURL(_ email: String) -> URL? {
        guard let address = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            !address.isEmpty
        else { return nil }
        return URL(string: "mailto:" + address)
    }

    /// Opens the card in Contacts.app itself.
    static func contactsURL(id: String) -> URL? {
        URL(string: "addressbook://" + id)
    }

    /// A postal address is stored one line per part; a row shows it as a single line.
    static func oneLine(_ address: String) -> String {
        address.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// "March 3" when the year is unknown, "March 3, 1990" when it is; nil for a part-empty date.
    static func birthday(_ birthday: DateComponents, calendar: Calendar, locale: Locale) -> String? {
        guard let month = birthday.month, let day = birthday.day else { return nil }
        var parts = DateComponents(year: birthday.year ?? 2000, month: month, day: day)
        parts.calendar = calendar
        guard let date = calendar.date(from: parts) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(birthday.year == nil ? "MMMMd" : "yMMMMd")
        return formatter.string(from: date)
    }

    private static func dialURL(_ scheme: String, _ phone: String) -> URL? {
        let number = dialable(phone)
        guard number.contains(where: \.isNumber) else { return nil }
        return URL(string: scheme + ":" + number)
    }
}
