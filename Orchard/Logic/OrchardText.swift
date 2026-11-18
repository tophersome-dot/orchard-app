import Foundation

enum OrchardText {
    static func folded(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_AU"))
            .lowercased()
    }

    static func words(_ value: String) -> [String] {
        folded(value).split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }

    static func compact(_ value: String) -> String {
        folded(value).unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
}
