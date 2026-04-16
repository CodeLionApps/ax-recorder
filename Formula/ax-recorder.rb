class AxRecorder < Formula
  desc "Record iOS Simulator UI interactions and export them as testID event logs"
  homepage "https://github.com/CodeLionApps/ax-recorder"
  url "https://github.com/CodeLionApps/ax-recorder/releases/download/v0.1.7/ax-recorder-macos.tar.gz"
  sha256 "720b5176e8a47ab7c0a1021df5235285bda58a5641614349d65df1a54e5d56a5"
  version "0.1.0"
  license "MIT"

  on_macos do
    depends_on xcode: ["14.0", :build]
  end

  def install
    bin.install "ax-recorder"
  end

  def caveats
    <<~EOS
      Before first use, grant Accessibility permissions to your terminal:
        System Settings → Privacy & Security → Accessibility → add Terminal (or iTerm2)

      Then run:
        ax-recorder              # auto-detect simulator
        ax-recorder -o log.json  # save to file
        ax-recorder --list       # list running simulators
        ax-recorder --pid 1234   # target specific simulator
    EOS
  end

  test do
    assert_match "Brak uruchomionych symulatorów", shell_output("#{bin}/ax-recorder --list 2>&1", 0)
  end
end
