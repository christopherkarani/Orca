#!/usr/bin/env sh
set -eu

VERSION="${ORCA_VERSION:-1.1.0}"
DIST_DIR="${ORCA_DIST_DIR:-dist}"
FORMULA="${ORCA_HOMEBREW_FORMULA:-packaging/homebrew/Formula/orca.rb}"
CHECKSUMS="${DIST_DIR}/checksums.txt"

fail() {
  printf 'update-homebrew-formula: %s\n' "$1" >&2
  exit 1
}

checksum_for() {
  name="$1"
  awk -v name="$name" '$2 == name {print $1}' "$CHECKSUMS"
}

[ -f "$FORMULA" ] || fail "formula not found: $FORMULA"
[ -f "$CHECKSUMS" ] || fail "checksums not found: $CHECKSUMS"

darwin_amd64="$(checksum_for "orca-v${VERSION}-darwin-amd64.tar.gz")"
darwin_arm64="$(checksum_for "orca-v${VERSION}-darwin-arm64.tar.gz")"
linux_amd64="$(checksum_for "orca-v${VERSION}-linux-amd64.tar.gz")"
linux_arm64="$(checksum_for "orca-v${VERSION}-linux-arm64.tar.gz")"

[ -n "$darwin_amd64" ] || fail "missing darwin amd64 checksum"
[ -n "$darwin_arm64" ] || fail "missing darwin arm64 checksum"
[ -n "$linux_amd64" ] || fail "missing linux amd64 checksum"
[ -n "$linux_arm64" ] || fail "missing linux arm64 checksum"

cat > "$FORMULA" <<EOF
class Orca < Formula
  desc "Local runtime firewall for AI agents"
  homepage "https://github.com/christopherkarani/Orca"
  version "${VERSION}"
  license "Apache-2.0"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/christopherkarani/Orca/releases/download/v#{version}/orca-v#{version}-darwin-arm64.tar.gz"
      sha256 "${darwin_arm64}"
    else
      url "https://github.com/christopherkarani/Orca/releases/download/v#{version}/orca-v#{version}-darwin-amd64.tar.gz"
      sha256 "${darwin_amd64}"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/christopherkarani/Orca/releases/download/v#{version}/orca-v#{version}-linux-arm64.tar.gz"
      sha256 "${linux_arm64}"
    else
      url "https://github.com/christopherkarani/Orca/releases/download/v#{version}/orca-v#{version}-linux-amd64.tar.gz"
      sha256 "${linux_amd64}"
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
      exec "#{libexec}/orca" "\$@"
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
EOF

printf 'Updated %s for Orca %s\n' "$FORMULA" "$VERSION"
