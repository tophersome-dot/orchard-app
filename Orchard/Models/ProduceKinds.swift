import Foundation

enum ProduceCategory: String, CaseIterable, Equatable {
    case apple
    case pear
    case grape
    case tropical
    case vegetable

    var title: String {
        switch self {
        case .apple: "Apples"
        case .pear: "Pears"
        case .grape: "Grapes"
        case .tropical: "Tropical"
        case .vegetable: "Vegetables"
        }
    }

    var singular: String {
        switch self {
        case .apple: "Apple"
        case .pear: "Pear"
        case .grape: "Grape"
        case .tropical: "Tropical"
        case .vegetable: "Vegetable"
        }
    }

    static func title(for raw: String) -> String {
        ProduceCategory(rawValue: raw)?.title ?? raw.capitalized
    }
}

enum FarmZone: String, CaseIterable, Equatable {
    case orchard
    case bed
    case trellis
    case greenhouse

    var title: String {
        switch self {
        case .orchard: "Orchard"
        case .bed: "Veg bed"
        case .trellis: "Trellis"
        case .greenhouse: "Lab greenhouse"
        }
    }
}

enum PlantForm: String, CaseIterable, Equatable {
    case apple
    case pear
    case mango
    case grape
    case carrot
    case tomato
}

enum FactStatus: String, Equatable {
    case verified
    case unverified
    case none
}

enum SeasonKind: String, Equatable {
    case harvest
    case retail
    case unspecified

    var heading: String {
        switch self {
        case .harvest: "Harvest months"
        case .retail: "In the shops"
        case .unspecified: "Season"
        }
    }
}

enum RecordKind: String, Equatable {
    case cultivar
    case marketType
}

enum SkinPattern: String, Equatable {
    case solid
    case blush
    case stripe
    case speckle
}
