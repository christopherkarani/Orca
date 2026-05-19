# Orca Homebrew Tap

This directory is the source for the `christopherkarani/homebrew-orca` tap.

## Release flow

```sh
./scripts/build-release.sh
# Ensure release assets are uploaded to GitHub before updating the formula
./scripts/update-homebrew-formula.sh
brew audit --strict --online packaging/homebrew/Formula/orca.rb
brew install --formula packaging/homebrew/Formula/orca.rb
brew test packaging/homebrew/Formula/orca.rb
```

## Publish flow

1. Create or update `https://github.com/christopherkarani/homebrew-orca`.
2. Copy `packaging/homebrew/Formula/orca.rb` to `Formula/orca.rb` in that tap.
3. Copy `packaging/homebrew/README.md` to `README.md` in that tap.
4. Commit and push after the matching GitHub Release assets are uploaded.

## User install

```sh
brew tap christopherkarani/orca
brew install orca
orca --version
orca doctor
```
