# Homebrew cask for Duplex. Lives in the tap repo (bnimit/homebrew-tap,
# path Casks/duplex.rb); this copy is the source of truth kept next to the
# app. After each release: bump `version`, paste the sha256 printed by
# scripts/release.sh, and copy this file into the tap repo.
#
# Users install with:
#   brew tap bnimit/tap
#   brew install --cask duplex
cask "duplex" do
  version "1.2.0"
  sha256 "4fd4f4fb8fce3901607dc28d9f1eca80704fda67fce3b4b7321af662b0d6bcf0"

  url "https://github.com/bnimit/duplex/releases/download/v#{version}/Duplex-#{version}.zip"
  name "Duplex"
  desc "Run multiple isolated instances of Electron apps, each with its own login"
  homepage "https://aetrixfoundry.com/"


  app "Duplex.app"

  zap trash: [
    "~/Library/Application Support/Duplex",
  ]

  caveats <<~EOS
    The first instance is free. A $5 license unlocks unlimited instances:
    https://aetrixfoundry.com/
  EOS
end
