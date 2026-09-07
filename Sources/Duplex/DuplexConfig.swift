import Foundation

enum DuplexConfig {
    /// Where "Buy for $5" sends people: the live Dodo Payments checkout for
    /// the Duplex license product.
    static let checkoutURL = URL(string: "https://checkout.dodopayments.com/buy/pdt_0NkwkzFX1SG8KYZfxVNCJ?quantity=1")!

    /// The newest published release. Read at most once a day to tell the user
    /// an update exists; nothing about them is sent with the request.
    static let releasesFeedURL = URL(string: "https://api.github.com/repos/bnimit/duplex/releases/latest")!

    /// This build's marketing version, shown in the status bar. Falls back to
    /// "dev" when running outside a bundle (swift run).
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    /// The command that upgrades a Homebrew install, offered in the update banner.
    static let upgradeCommand = "brew upgrade --cask duplex"
}
