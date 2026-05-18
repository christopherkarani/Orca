class Orca < Formula
  desc "Local runtime firewall for AI agents"
  homepage "https://github.com/christopherkarani/Orca"
  version "1.1.0"
  license "Apache-2.0"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/christopherkarani/Orca/releases/download/v#{version}/orca-v#{version}-darwin-arm64.tar.gz"
      sha256 "81cf09553da5032cb07fbaefe63022e267f66671793676c234fffc7d2b3de807"
    else
      url "https://github.com/christopherkarani/Orca/releases/download/v#{version}/orca-v#{version}-darwin-amd64.tar.gz"
      sha256 "299ebf4dd1fae496e7916dca99b4b215bbd4a4d5c6becffb2d5de3dc1e7086f9"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/christopherkarani/Orca/releases/download/v#{version}/orca-v#{version}-linux-arm64.tar.gz"
      sha256 "ac3ae9cdc7b778183e50d6d77a5c1a412d32381bcc0c12abacf49551605bd41d"
    else
      url "https://github.com/christopherkarani/Orca/releases/download/v#{version}/orca-v#{version}-linux-amd64.tar.gz"
      sha256 "4a793bc1209540a15fff1d6984907c6829b661f0a746f549cc17967661cc4247"
    end
  end

  def install
    libexec.install "bin/orca" if File.exist?("bin/orca")
    pkgshare.install "docs" if Dir.exist?("docs")
    pkgshare.install "examples" if Dir.exist?("examples")
    pkgshare.install "fixtures" if Dir.exist?("fixtures")
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
