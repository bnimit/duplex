import Foundation

public enum BadgeColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, purple, pink
    public var id: String { rawValue }
}

public enum IconChoice: Equatable {
    /// An exact, full-resolution copy of the target app's own icon, with no badge. This is
    /// the default for new instances. Falls back to a rendered (unbadged) icon when the
    /// target has no usable .icns (e.g. Assets.car-only apps).
    case original
    case badge(BadgeColor)
    case custom(URL)
    /// Preserve whatever icon the wrapper being regenerated already has (used when editing
    /// an instance without changing its icon). Falls back to `.badge(.blue)` when there is
    /// no prior wrapper to copy from (e.g. first-time generation).
    case keepExisting
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
