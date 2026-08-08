import Foundation

enum DuplexConfig {
    /// Where "Buy for $5" sends people. Points at the product page until the
    /// merchant-of-record checkout exists; swap to the real checkout URL
    /// (and cut a release) the day the store goes live.
    static let checkoutURL = URL(string: "https://aetrixfoundry.com/duplex")!
}
