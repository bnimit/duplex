public enum DuplexPlistKey {
    public static let targetBundleID = "DuplexTargetBundleID"
    public static let targetPath = "DuplexTargetPath"
    /// CFBundleExecutable of the target app, i.e. the binary that sits next to the launcher in a clone.
    public static let targetExecutable = "DuplexTargetExecutable"
    public static let instanceSlug = "DuplexInstanceSlug"
    public static let instanceName = "DuplexInstanceName"
    /// 1 (or absent): 1.1 thin wrapper. 2: cloned app with its own identity.
    public static let formatVersion = "DuplexFormatVersion"
    /// Version of the target app the clone was made from; see InstancePlist.sourceVersion(of:).
    public static let sourceVersion = "DuplexSourceVersion"
    public static let currentFormatVersion = 2
    public static let bundleIDPrefix = "com.duplex."
}
