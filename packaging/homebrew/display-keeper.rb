cask "display-keeper" do
  version "__VERSION__"
  sha256 "__SHA256__"

  url "https://github.com/favoretti/display-keeper/releases/download/v#{version}/DisplayKeeper-#{version}.zip"
  name "Display Keeper"
  desc "Restores external monitor and window layout after wake"
  homepage "https://github.com/favoretti/display-keeper"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :ventura"

  app "DisplayKeeper.app"
  binary "#{appdir}/DisplayKeeper.app/Contents/Resources/display-keeper"

  zap trash: [
    "~/Library/Application Support/DisplayKeeper",
    "~/Library/Caches/io.github.favoretti.DisplayKeeper",
    "~/Library/HTTPStorages/io.github.favoretti.DisplayKeeper",
    "~/Library/Preferences/io.github.favoretti.DisplayKeeper.plist",
  ]
end
