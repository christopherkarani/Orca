class Orca < Formula
  desc "Local runtime firewall for AI agents"
  homepage "https://github.com/christopherkarani/Orca"
  version "1.2.2"
  license "Apache-2.0"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/christopherkarani/Orca/releases/download/v#{version}/orca-v#{version}-darwin-arm64.tar.gz"
      sha256 "{{DARWIN_ARM64_SHA256}}"
    else
      url "https://github.com/christopherkarani/Orca/releases/download/v#{version}/orca-v#{version}-darwin-amd64.tar.gz"
      sha256 "{{DARWIN_AMD64_SHA256}}"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/christopherkarani/Orca/releases/download/v#{version}/orca-v#{version}-linux-arm64.tar.gz"
      sha256 "{{LINUX_ARM64_SHA256}}"
    else
      url "https://github.com/christopherkarani/Orca/releases/download/v#{version}/orca-v#{version}-linux-amd64.tar.gz"
      sha256 "{{LINUX_AMD64_SHA256}}"
    end
  end

  def install
    bin.install "bin/orca"
    bin.install "bin/orca-daemon"
    pkgshare.install "orca-dashboard-ui"
    pkgshare.install "integrations"
    pkgshare.install "fixtures"
    pkgshare.install "schemas"
    pkgshare.install "policies"
    # manifest status: exists — (exists) runtime assets and plugin manifest hermes verified at packaging time
  end

  def caveats
    <<~EOS
      Orca runtime assets are installed at:
        #{pkgshare}

      To use orca in this terminal right now, run:

          export PATH="#{bin}:$PATH"
          export ORCA_RESOURCE_ROOT="#{pkgshare}"

      (These two lines are the same contract used by the curl|sh installer.)
    EOS
  end

  test do
    ENV["ORCA_RESOURCE_ROOT"] = pkgshare
    assert_match version.to_s, shell_output("#{bin}/orca --version")
    # Exercise the full runtime contract (matching install.sh + DX smoke tests)
    system "#{bin}/orca", "doctor"
    system "#{bin}/orca", "packs", "--help"
    system "#{bin}/orca", "plugin", "doctor", "hermes", "--json"
    system "#{bin}/orca", "redteam", "--ci"
  end
end
