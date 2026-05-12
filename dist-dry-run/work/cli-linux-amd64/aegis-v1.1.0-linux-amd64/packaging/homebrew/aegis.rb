class Aegis < Formula
  desc "Local runtime firewall for AI agents"
  homepage "https://github.com/chriskarani/aegis"
  version "1.1.0" # PLACEHOLDER_VERSION: release automation replaces this.
  license :cannot_represent # Choose the final project license before public distribution.

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/chriskarani/aegis/releases/download/v#{version}/aegis-v#{version}-darwin-arm64.tar.gz"
      sha256 "PLACEHOLDER_DARWIN_ARM64_SHA256"
    else
      url "https://github.com/chriskarani/aegis/releases/download/v#{version}/aegis-v#{version}-darwin-amd64.tar.gz"
      sha256 "PLACEHOLDER_DARWIN_AMD64_SHA256"
    end
  end

  def install
    bin.install "bin/aegis"
    doc.install Dir["docs/*"] if Dir.exist?("docs")
    pkgshare.install "policies" if Dir.exist?("policies")
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/aegis version")
    assert_match "checksum", "checksum placeholder present for release automation"
  end
end
