import Foundation

public enum BadgeColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, purple, pink
    public var id: String { rawValue }
}

public enum IconChoice: Equatable {
    case badge(BadgeColor)
    case custom(URL)
}

public struct InstanceSpec {
    public let name: String
    public let slug: String
    public let target: TargetApp

    public init(name: String, slug: String, target: TargetApp) {
        self.name = name
        self.slug = slug
        self.target = target
    }
}
