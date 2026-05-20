class Orca < Formula
  desc "Local runtime firewall for AI agents"
  homepage "https://github.com/christopherkarani/Orca"
  version "1.1.1"
  license "Apache-2.0"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/christopherkarani/Orca/releases/download/v#{version}/orca-v#{version}-darwin-arm64.tar.gz"
      sha256 "2ac61814f7603bb41a293948fca9a09585c7073458a33c35b3ca3ef7c8892405"
    else
      url "https://github.com/christopherkarani/Orca/releases/download/v#{version}/orca-v#{version}-darwin-amd64.tar.gz"
      sha256 "28044dd1c3e4b120826ccb3e3787e25048a9a6ddce8ec8b444b84b0085928a7f"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/christopherkarani/Orca/releases/download/v#{version}/orca-v#{version}-linux-arm64.tar.gz"
      sha256 "3c28eef2324f7dbcfafd10ad83ba7707f2c6f4125a3925892898ee25a7f5a116"
    else
      url "https://github.com/christopherkarani/Orca/releases/download/v#{version}/orca-v#{version}-linux-amd64.tar.gz"
      sha256 "3f49e9265bce4f043642b84552d92b8d33f235a0be30a5b82d5d830bf4efa2e0"
    end
  end

  def install
    bin.install "bin/orca"
    prefix.install "orca-dashboard-ui/dist" => "orca-dashboard-ui/dist"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/orca --version")
  end
end
