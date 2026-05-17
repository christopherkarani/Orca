# Orca Homebrew Tap

This directory is the source for the `christopherkarani/homebrew-orca` tap.

Release flow:

```sh
./scripts/build-release.sh
./scripts/update-homebrew-formula.sh
brew audit --strict --online packaging/homebrew/Formula/orca.rb
brew install --build-from-source packaging/homebrew/Formula/orca.rb
brew test packaging/homebrew/Formula/orca.rb
```

Publish flow:

1. Create or update `https://github.com/christopherkarani/homebrew-orca`.
2. Copy `packaging/homebrew/Formula/orca.rb` to `Formula/orca.rb` in that tap.
3. Commit the formula update after the matching GitHub Release assets are uploaded.

The formula uses release archive SHA-256 checksum values from `dist/checksums.txt`.

User install after the tap exists:

```sh
brew tap christopherkarani/orca
brew install orca
orca plugin install hermes --yes
```
