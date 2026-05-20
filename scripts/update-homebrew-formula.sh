#!/usr/bin/env sh
set -eu

VERSION="${1:-${ORCA_VERSION:-}}"
HOMEBREW_TAP_DIR="${ORCA_HOMEBREW_TAP_DIR:-${HOME}/code/homebrew-orca}"
FORMULA_OUT="${ORCA_HOMEBREW_FORMULA:-${HOMEBREW_TAP_DIR}/Formula/orca.rb}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/orca-homebrew.XXXXXX")"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

fail() {
  printf 'update-homebrew-formula: %s\n' "$1" >&2
  exit 1
}

[ -n "$VERSION" ] || fail "usage: $0 <version>  (or set ORCA_VERSION)"

DIST_DIR="${ORCA_DIST_DIR:-}"
USE_LOCAL=0
if [ -n "$DIST_DIR" ] && [ -f "${DIST_DIR}/checksums.txt" ]; then
  USE_LOCAL=1
  printf 'Using local release assets from %s\n' "$DIST_DIR"
fi

if [ "$USE_LOCAL" -eq 0 ]; then
  BASE_URL="https://github.com/christopherkarani/Orca/releases/download/v${VERSION}"
  printf 'Downloading release assets for Orca %s...\n' "$VERSION"

  for plat in darwin-arm64 darwin-amd64 linux-arm64 linux-amd64; do
    artifact="orca-v${VERSION}-${plat}.tar.gz"
    url="${BASE_URL}/${artifact}"
    output="${TMP_DIR}/${artifact}"

    printf '  → %s\n' "$artifact"
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL -o "$output" "$url" || fail "failed to download $url"
    elif command -v wget >/dev/null 2>&1; then
      wget -q -O "$output" "$url" || fail "failed to download $url"
    else
      fail "curl or wget is required"
    fi
  done
fi

sha256_file() {
  file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    fail "sha256sum or shasum is required"
  fi
}

if [ "$USE_LOCAL" -eq 1 ]; then
  checksum_for() {
    name="$1"
    awk -v name="$name" '$2 == name {print $1}' "${DIST_DIR}/checksums.txt"
  }
  darwin_arm64="$(checksum_for "orca-v${VERSION}-darwin-arm64.tar.gz")"
  darwin_amd64="$(checksum_for "orca-v${VERSION}-darwin-amd64.tar.gz")"
  linux_arm64="$(checksum_for "orca-v${VERSION}-linux-arm64.tar.gz")"
  linux_amd64="$(checksum_for "orca-v${VERSION}-linux-amd64.tar.gz")"
else
  darwin_arm64="$(sha256_file "${TMP_DIR}/orca-v${VERSION}-darwin-arm64.tar.gz")"
  darwin_amd64="$(sha256_file "${TMP_DIR}/orca-v${VERSION}-darwin-amd64.tar.gz")"
  linux_arm64="$(sha256_file "${TMP_DIR}/orca-v${VERSION}-linux-arm64.tar.gz")"
  linux_amd64="$(sha256_file "${TMP_DIR}/orca-v${VERSION}-linux-amd64.tar.gz")"
fi

printf 'Generating formula...\n'

mkdir -p "$(dirname "$FORMULA_OUT")"

cat > "$FORMULA_OUT" <<EOF
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
    bin.install "bin/orca"
    prefix.install "orca-dashboard-ui/dist" => "orca-dashboard-ui/dist"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/orca --version")
  end
end
EOF

printf 'Formula written to %s\n' "$FORMULA_OUT"

# Optionally commit and push to the tap repo
if [ -d "${HOMEBREW_TAP_DIR}/.git" ]; then
  cd "$HOMEBREW_TAP_DIR"
  git add Formula/orca.rb
  if git diff --cached --quiet; then
    printf 'No changes to commit.\n'
  else
    git commit -m "Update orca to ${VERSION}"
    printf 'Committed. Run `git push` to publish.\n'
  fi
else
  printf 'Note: %s is not a git repo. Skipping commit.\n' "$HOMEBREW_TAP_DIR"
fi
