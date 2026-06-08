#!/usr/bin/env bash
set -euo pipefail

# CLI version checker for pack maintenance.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSIONS_FILE="${ROOT_DIR}/docs/cli-versions.yaml"

usage() {
  cat <<'EOF'
Usage: scripts/check_cli_versions.sh [--offline] [--help]

Checks docs/cli-versions.yaml against upstream release sources. The audit exits
non-zero when a tracked CLI has a newer release family that is not covered by
tested_versions, or when release metadata cannot be fetched.

Options:
  --offline  Use only ORCA_CLI_VERSION_AUDIT_RELEASES_JSON fixture data.
  --help     Show this help.

Environment:
  GITHUB_TOKEN
      Optional token used for GitHub release API requests.
  ORCA_CLI_VERSION_AUDIT_RELEASES_JSON
      Optional JSON object mapping entry ids or tool names to latest versions.
      Example: {"secrets.vault":"1.16.9","rclone":"1.66.4","gh":"2.45.1"}
EOF
}

OFFLINE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --offline)
      OFFLINE=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -f "$VERSIONS_FILE" ]]; then
  echo "Missing ${VERSIONS_FILE}" >&2
  exit 1
fi

if ! command -v ruby >/dev/null 2>&1; then
  echo "ruby is required for CLI version audit YAML parsing" >&2
  exit 1
fi

export ORCA_CLI_VERSION_AUDIT_OFFLINE="$OFFLINE"

ruby - "$VERSIONS_FILE" <<'RUBY'
require "date"
require "json"
require "net/http"
require "uri"
require "yaml"

Version = Struct.new(:major, :minor, :patch, :raw) do
  include Comparable

  def <=>(other)
    [major, minor, patch] <=> [other.major, other.minor, other.patch]
  end

  def label
    "#{major}.#{minor}.#{patch}"
  end
end

def parse_version(value)
  match = value.to_s.match(/[vV]?(\d+)\.(\d+)(?:\.(\d+))?/)
  return nil unless match

  Version.new(match[1].to_i, match[2].to_i, (match[3] || "0").to_i, value.to_s)
end

def parse_tested_spec(value)
  text = value.to_s.strip.sub(/\A[vV]/, "")
  parts = text.split(".")
  return nil if parts.length < 2 || parts.length > 3

  parts << "x" while parts.length < 3
  wildcards = []
  numbers = []

  parts.each do |part|
    if part.downcase == "x" || part == "*"
      wildcards << true
      numbers << 0
    elsif part.match?(/\A\d+\z/)
      wildcards << false
      numbers << part.to_i
    else
      return nil
    end
  end

  { raw: value.to_s, numbers: numbers, wildcards: wildcards }
end

def spec_covers_version?(spec, version)
  values = [version.major, version.minor, version.patch]
  spec[:numbers].each_with_index.all? do |number, index|
    spec[:wildcards][index] || number == values[index]
  end
end

def github_repo_from_releases_url(url)
  uri = URI(url)
  match = uri.path.match(%r{\A/([^/]+)/([^/]+)/releases/?\z})
  return nil unless uri.host == "github.com" && match

  "#{match[1]}/#{match[2]}"
rescue URI::InvalidURIError
  nil
end

def http_get(url)
  uri = URI(url)
  request = Net::HTTP::Get.new(uri)
  request["User-Agent"] = "orca-cli-version-audit"

  if uri.host == "api.github.com"
    request["Accept"] = "application/vnd.github+json"
    token = ENV.fetch("GITHUB_TOKEN", "")
    request["Authorization"] = "Bearer #{token}" unless token.empty?
  end

  response = Net::HTTP.start(
    uri.host,
    uri.port,
    use_ssl: uri.scheme == "https",
    open_timeout: 10,
    read_timeout: 20
  ) { |http| http.request(request) }

  unless response.is_a?(Net::HTTPSuccess)
    raise "GET #{url} returned HTTP #{response.code}"
  end

  response.body
end

def latest_from_github(repo)
  body = http_get("https://api.github.com/repos/#{repo}/releases/latest")
  data = JSON.parse(body)
  version = parse_version(data["tag_name"] || data["name"])
  raise "GitHub latest release for #{repo} did not include a semver tag" unless version

  version
end

def latest_from_changelog(url)
  body = http_get(url)
  heading_matches = body.scan(%r{<h[12][^>]*>\s*[vV](\d+\.\d+(?:\.\d+)?)\s+-\s+\d{4}-\d{2}-\d{2}}i)
  raw_versions = heading_matches.flatten
  raw_versions = body.scan(/(?<![\d.])[vV](\d+\.\d+(?:\.\d+)?)(?![\d.])/).flatten if raw_versions.empty?

  versions = raw_versions.filter_map do |raw|
    parse_version("v#{raw}")
  end
  raise "No semver releases found at #{url}" if versions.empty?

  versions.max
end

def fixture_value(fixtures, entry_id, config)
  value = fixtures[entry_id] || fixtures[config.fetch("tool", "")]
  value.is_a?(Hash) ? value["latest"] : value
end

def latest_version_for(entry_id, config, fixtures, offline)
  if (fixture = fixture_value(fixtures, entry_id, config))
    version = parse_version(fixture)
    raise "Fixture for #{entry_id} is not a semver value: #{fixture.inspect}" unless version

    return version
  end

  raise "No fixture provided for #{entry_id} in --offline mode" if offline

  changelog_url = config.fetch("changelog_url")
  if (repo = github_repo_from_releases_url(changelog_url))
    latest_from_github(repo)
  else
    latest_from_changelog(changelog_url)
  end
end

def gha_escape(value)
  value.to_s.gsub("%", "%25").gsub("\r", "%0D").gsub("\n", "%0A")
end

def annotate(kind, title, message)
  return unless ENV["GITHUB_ACTIONS"] == "true"

  puts "::#{kind} title=#{gha_escape(title)}::#{gha_escape(message)}"
end

def append_summary(rows, failures)
  path = ENV["GITHUB_STEP_SUMMARY"]
  return if path.to_s.empty?

  File.open(path, "a") do |file|
    file.puts "## CLI Version Audit"
    file.puts
    file.puts "| Pack | Tool | Tested | Latest | Status |"
    file.puts "| --- | --- | --- | --- | --- |"
    rows.each do |row|
      file.puts "| `#{row[:id]}` | `#{row[:tool]}` | `#{row[:tested]}` | `#{row[:latest]}` | #{row[:status]} |"
    end
    unless failures.empty?
      file.puts
      file.puts "### Action Required"
      failures.each do |failure|
        file.puts "- `#{failure[:id]}`: #{failure[:message]}"
      end
    end
  end
end

versions_file = ARGV.fetch(0)
offline = ENV["ORCA_CLI_VERSION_AUDIT_OFFLINE"] == "1"
fixtures_json = ENV.fetch("ORCA_CLI_VERSION_AUDIT_RELEASES_JSON", "")
fixtures = fixtures_json.empty? ? {} : JSON.parse(fixtures_json)

data = YAML.safe_load_file(
  versions_file,
  permitted_classes: [Date],
  aliases: false
)

unless data.is_a?(Hash) && !data.empty?
  warn "Expected #{versions_file} to contain a non-empty mapping"
  exit 1
end

rows = []
failures = []

data.each do |entry_id, config|
  unless config.is_a?(Hash)
    failures << { id: entry_id, message: "entry must be a mapping" }
    next
  end

  missing = %w[tool tested_versions last_verified changelog_url].reject { |key| config.key?(key) }
  unless missing.empty?
    failures << { id: entry_id, message: "missing required keys: #{missing.join(", ")}" }
    next
  end

  tested_versions = config["tested_versions"]
  unless tested_versions.is_a?(Array) && !tested_versions.empty?
    failures << { id: entry_id, message: "tested_versions must be a non-empty list" }
    next
  end

  specs = tested_versions.map { |value| parse_tested_spec(value) }
  if specs.any?(&:nil?)
    failures << {
      id: entry_id,
      message: "tested_versions must use semver specs like 1.16.x or 2.45.0"
    }
    next
  end

  begin
    latest = latest_version_for(entry_id, config, fixtures, offline)
  rescue StandardError => error
    failures << { id: entry_id, message: error.message }
    next
  end

  covered = specs.any? { |spec| spec_covers_version?(spec, latest) }
  tested_label = tested_versions.join(", ")
  status = covered ? "ok" : "drift"
  rows << {
    id: entry_id,
    tool: config["tool"],
    tested: tested_label,
    latest: latest.label,
    status: status
  }

  next if covered

  failures << {
    id: entry_id,
    message: "#{config["tool"]} latest #{latest.label} is not covered by tested_versions [#{tested_label}]. " \
             "Review #{config["changelog_url"]}, update pack patterns/tests if needed, then add the " \
             "new release family to docs/cli-versions.yaml."
  }
end

puts "CLI version audit: #{versions_file}"
puts
rows.each do |row|
  marker = row[:status] == "ok" ? "OK" : "DRIFT"
  puts "#{marker} #{row[:id]} (#{row[:tool]}): tested #{row[:tested]}, latest #{row[:latest]}"
end

unless failures.empty?
  puts
  puts "Action required:"
  failures.each do |failure|
    puts "- #{failure[:id]}: #{failure[:message]}"
    annotate("error", "CLI version audit: #{failure[:id]}", failure[:message])
  end
end

append_summary(rows, failures)
exit(failures.empty? ? 0 : 1)
RUBY
