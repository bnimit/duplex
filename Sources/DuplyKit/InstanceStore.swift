import Foundation

public struct Instance: Equatable, Identifiable {
    public var id: String { slug }
    public let wrapperURL: URL
    public let name: String
    public let slug: String
    public let targetBundleID: String
    public let targetPath: String
    public let urlSchemes: [String]
    public let dataDir: URL
}

public enum InstanceStore {
    public static func scan(outputDir: URL, homePath: String) -> [Instance] {
        let fm = FileManager.default
        let bundles = (try? fm.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        var instances: [Instance] = []
        for bundle in bundles where bundle.pathExtension == "app" {
            let plistURL = bundle.appendingPathComponent("Contents/Info.plist")
            guard let data = try? Data(contentsOf: plistURL),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let slug = plist[DuplyPlistKey.instanceSlug] as? String,
                  let targetBundleID = plist[DuplyPlistKey.targetBundleID] as? String,
                  let targetPath = plist[DuplyPlistKey.targetPath] as? String
            else { continue }
            let name = plist[DuplyPlistKey.instanceName] as? String ?? slug
            var schemes: [String] = []
            if let urlTypes = plist["CFBundleURLTypes"] as? [[String: Any]] {
                for entry in urlTypes {
                    schemes.append(contentsOf: entry["CFBundleURLSchemes"] as? [String] ?? [])
                }
            }
            instances.append(Instance(
                wrapperURL: bundle, name: name, slug: slug,
                targetBundleID: targetBundleID, targetPath: targetPath,
                urlSchemes: schemes,
                dataDir: LauncherLogic.dataDir(slug: slug, homePath: homePath)))
        }
        return instances.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func dataSize(of instance: Instance) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: instance.dataDir, includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
            options: [], errorHandler: nil)
        else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    public static func delete(_ instance: Instance, includingData: Bool) throws {
        let fm = FileManager.default
        // Trash is friendlier than rm; fall back to remove if trashing is unavailable (e.g. tmpfs in tests).
        do { try fm.trashItem(at: instance.wrapperURL, resultingItemURL: nil) }
        catch { try fm.removeItem(at: instance.wrapperURL) }
        if includingData, fm.fileExists(atPath: instance.dataDir.path) {
            // Remove the whole <slug> folder, not just <slug>/data.
            let slugRoot = instance.dataDir.deletingLastPathComponent()
            do { try fm.trashItem(at: slugRoot, resultingItemURL: nil) }
            catch { try fm.removeItem(at: slugRoot) }
        }
    }
}
