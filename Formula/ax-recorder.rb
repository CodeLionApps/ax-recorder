class AxRecorder < Formula
  desc "Record iOS Simulator UI interactions and export them as testID event logs"
  homepage "https://github.com/CodeLionApps/ax-recorder"
  url "https://github.com/CodeLionApps/ax-recorder/releases/download/v0.1.6/ax-recorder-macos.tar.gz"
  sha256 "3dd3dff111b0e40e75668663a70f061af156e2c60b18c77c01f7e33e53197567"
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
