# Homebrew cask for Duplex. Lives in the tap repo (bnimit/homebrew-tap,
# path Casks/duplex.rb); this copy is the source of truth kept next to the
# app. After each release: bump `version`, paste the sha256 printed by
# scripts/release.sh, and copy this file into the tap repo.
#
# Users install with:
#   brew tap bnimit/tap
#   brew install --cask duplex
cask "duplex" do
  version "1.1"
  sha256 "REPLACE_WITH_SHA256_FROM_RELEASE_SCRIPT"

  url "https://github.com/bnimit/duplex/releases/download/v#{version}/Duplex-#{version}.zip"
  name "Duplex"
  desc "Run multiple isolated instances of Electron apps, each with its own login"
  homepage "https://aetrixfoundry.com/"

  depends_on macos: ">= :ventura"

  app "Duplex.app"

  zap trash: [
    "~/Library/Application Support/Duplex",
  ]

  caveats <<~EOS
    The first instance is free. A $5 license unlocks unlimited instances:
    https://aetrixfoundry.com/
  EOS
end
