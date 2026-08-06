import Foundation

/// The single licensing rule. Regenerating an existing instance (Edit) is
/// always free; only creating a net-new instance beyond the first requires
/// a license. Launch/edit/delete/routing are never gated, and the launcher
/// inside wrappers never checks the license.
public enum LicenseGate {
    public static func canCreate(existingCount: Int, isRegeneration: Bool, licensed: Bool) -> Bool {
        if isRegeneration { return true }
        return licensed || existingCount < 1
    }
}
