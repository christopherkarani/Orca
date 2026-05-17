class Orca < Formula
  desc "Local runtime firewall for AI agents"
  homepage "https://github.com/christopherkarani/Orca"
  version "1.1.0"
  license "Apache-2.0"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/christopherkarani/Orca/releases/download/v#{version}/orca-v#{version}-darwin-arm64.tar.gz"
      sha256 "ddea96687af3a84c1578a23d07fd5b231f237dcac50de8e9768dcb002a588681"
    else
      url "https://github.com/christopherkarani/Orca/releases/download/v#{version}/orca-v#{version}-darwin-amd64.tar.gz"
      sha256 "b70e72f1102f390ebd34c22478ffbc0475db7ad23fc0137c9c070ce6cda55357"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/christopherkarani/Orca/releases/download/v#{version}/orca-v#{version}-linux-arm64.tar.gz"
      sha256 "6b9e0191bff97cb3958a1ff0cc7a208b392b11319f2ac344457acb2b40491ba2"
    else
      url "https://github.com/christopherkarani/Orca/releases/download/v#{version}/orca-v#{version}-linux-amd64.tar.gz"
      sha256 "56b4179d30cd5d0f325cbe20ead36fedbc07a26722bc959e6b5a33c1dbf9e318"
    end
  end

  def install
    libexec.install "bin/orca" if File.exist?("bin/orca")
    pkgshare.install "docs" if Dir.exist?("docs")
    pkgshare.install "examples" if Dir.exist?("examples")
    pkgshare.install "integrations" if Dir.exist?("integrations")
    pkgshare.install "policies" if Dir.exist?("policies")
    pkgshare.install "schemas" if Dir.exist?("schemas")

    (bin/"orca").write <<~EOS
      #!/bin/sh
      export ORCA_RESOURCE_ROOT="#{pkgshare}"
      exec "#{libexec}/orca" "$@"
    EOS
    chmod 0755, bin/"orca"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/orca version")
    hermes_manifest = shell_output("#{bin}/orca plugin manifest hermes")
    assert_match "Hermes plugin manifest", hermes_manifest
    assert_match "manifest status: exists", hermes_manifest
    assert_match "(exists)", hermes_manifest
  end
end
