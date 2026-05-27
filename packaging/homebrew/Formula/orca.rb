class Orca < Formula
  desc "Local runtime firewall for AI agents"
  homepage "https://github.com/christopherkarani/Orca"
  version "1.1.5"
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
    prefix.install "orca-dashboard-ui/dist" => "orca-dashboard-ui/dist"
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

      Add to your shell profile:
        export ORCA_RESOURCE_ROOT="#{pkgshare}"
    EOS
  end

  test do
    ENV["ORCA_RESOURCE_ROOT"] = pkgshare
    assert_match version.to_s, shell_output("#{bin}/orca --version")
    system "#{bin}/orca", "plugin", "manifest", "hermes"
  end
end
