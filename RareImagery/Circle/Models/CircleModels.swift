import Foundation
import SwiftData

enum CircleType: String, Codable, CaseIterable, Identifiable {
    case closeFriends = "Close Friends"
    case coPromote = "Co-Promote"
    case all = "All Circles"

    var id: String { rawValue }
}

enum FavoriteType: String, Codable, CaseIterable, Identifiable {
    case creator
    case productDraft
    case design

    var id: String { rawValue }

    var label: String {
        switch self {
        case .creator: return "Creators"
        case .productDraft: return "Drafts"
        case .design: return "Designs"
        }
    }
}

enum CircleSegment: String, CaseIterable, Identifiable {
    case discover = "Discover"
    case myCircle = "My Circle"
    case favorites = "Favorites"

    var id: String { rawValue }
}

@Model
final class CircleMember {
    var id: UUID
    @Attribute(.unique) var xUserID: String
    var username: String
    var displayName: String
    var profileImageURL: String?
    var addedDate: Date
    var isFavorite: Bool
    var circleTypeRaw: String

    var circleType: CircleType {
        get { CircleType(rawValue: circleTypeRaw) ?? .closeFriends }
        set { circleTypeRaw = newValue.rawValue }
    }

    init(
        xUserID: String,
        username: String,
        displayName: String,
        profileImageURL: String? = nil,
        circleType: CircleType = .closeFriends,
        isFavorite: Bool = false,
        addedDate: Date = .now
    ) {
        self.id = UUID()
        self.xUserID = xUserID
        self.username = username
        self.displayName = displayName
        self.profileImageURL = profileImageURL
        self.addedDate = addedDate
        self.isFavorite = isFavorite
        self.circleTypeRaw = circleType.rawValue
    }
}

extension CircleMember: Identifiable {}

@Model
final class FavoriteItem {
    var id: UUID
    var itemTypeRaw: String
    @Attribute(.unique) var referenceID: String
    var title: String
    var imageURL: String?
    var addedDate: Date

    var itemType: FavoriteType {
        get { FavoriteType(rawValue: itemTypeRaw) ?? .creator }
        set { itemTypeRaw = newValue.rawValue }
    }

    init(
        itemType: FavoriteType,
        referenceID: String,
        title: String,
        imageURL: String? = nil,
        addedDate: Date = .now
    ) {
        self.id = UUID()
        self.itemTypeRaw = itemType.rawValue
        self.referenceID = referenceID
        self.title = title
        self.imageURL = imageURL
        self.addedDate = addedDate
    }
}

extension FavoriteItem: Identifiable {}
