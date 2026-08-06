import Foundation

/// Live-search predicate for the instance list: matches on the instance
/// name or the target app's display name, case- and diacritic-insensitive.
public enum InstanceFilter {
    public static func matches(name: String, targetPath: String, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        let appName = URL(fileURLWithPath: targetPath).deletingPathExtension().lastPathComponent
        return name.localizedStandardContains(q) || appName.localizedStandardContains(q)
    }
}
