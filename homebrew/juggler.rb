cask "juggler" do
  version "1.0.0"
  sha256 "e6691956f2f0fd90bb1380fc59010a296182cbc6a069999d7556876b27b6dc9a"

  url "https://github.com/nielsmadan/juggler/releases/download/v#{version}/Juggler.zip"
  name "Juggler"
  desc "Global hotkey navigation for Claude Code sessions"
  homepage "https://github.com/nielsmadan/juggler"

  depends_on macos: ">= :sonoma"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "Juggler.app"

  zap trash: [
    "~/Library/Application Support/Juggler",
    "~/Library/Preferences/com.nielsmadan.Juggler.plist",
    "~/Library/Caches/com.nielsmadan.Juggler",
  ]
end
