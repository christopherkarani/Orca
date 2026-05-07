const std = @import("std");

pub const RedactionMatch = struct {
    label: []const u8,
    fingerprint: [8]u8,
};

const EnvAssignment = struct {
    name: []const u8,
    value: []const u8,
};

pub const redacted_value = "[REDACTED]";

const secret_env_patterns = [_][]const u8{
    "*TOKEN*",
    "*SECRET*",
    "*PASSWORD*",
    "*PASSWD*",
    "*PRIVATE*",
    "*KEY*",
    "AWS_*",
    "AZURE_*",
    "GITHUB_TOKEN",
    "GH_TOKEN",
    "OPENAI_API_KEY",
    "ANTHROPIC_API_KEY",
    "GOOGLE_API_KEY",
    "GOOGLE_APPLICATION_CREDENTIALS",
    "NPM_TOKEN",
    "PYPI_TOKEN",
    "SSH_AUTH_SOCK",
};

pub fn redactString(value: []const u8) []const u8 {
    var buf: [256]u8 = undefined;
    const redacted = redactStringBounded(value, &buf);
    if (redacted.ptr == value.ptr and redacted.len == value.len) return value;
    return redacted_value;
}

pub fn redactStringBounded(value: []const u8, buffer: []u8) []const u8 {
    if (classifyString(value)) |match| {
        return formatReplacement(buffer, match.label, &match.fingerprint) catch redacted_value;
    }
    return value;
}

pub fn redactTargetValueBounded(kind_name: []const u8, value: []const u8, buffer: []u8) []const u8 {
    if (std.mem.eql(u8, kind_name, "env_var")) {
        if (classifySecretValue(value)) |match| {
            return formatReplacement(buffer, match.label, &match.fingerprint) catch redacted_value;
        }
        return value;
    }
    return redactStringBounded(value, buffer);
}

pub fn isSecretEnvName(name: []const u8) bool {
    for (secret_env_patterns) |pattern| {
        if (matchesPatternIgnoreCase(pattern, name)) return true;
    }
    return false;
}

pub fn classifyString(value: []const u8) ?RedactionMatch {
    if (parseEnvAssignment(value)) |assignment| {
        if (isSecretEnvName(assignment.name)) {
            return .{ .label = assignment.name, .fingerprint = fingerprint8(assignment.value) };
        }
        if (classifySecretValue(assignment.value)) |match| return match;
    }
    if (classifyEmbeddedAssignment(value)) |match| return match;
    if (classifyEmbeddedSecretToken(value)) |match| return match;
    return classifySecretValue(value);
}

pub fn classifySecretValue(value: []const u8) ?RedactionMatch {
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    if (trimmed.len == 0) return null;

    if (containsIgnoreCase(trimmed, "fake_secret") or containsIgnoreCase(trimmed, "fake-secret") or containsIgnoreCase(trimmed, "secret_value") or containsIgnoreCase(trimmed, "secret-value")) {
        return .{ .label = "secret:synthetic_secret", .fingerprint = fingerprint8(trimmed) };
    }
    if (containsIgnoreCase(trimmed, "-----BEGIN ") and containsIgnoreCase(trimmed, "PRIVATE KEY-----")) {
        return .{ .label = "secret:pem_private_key", .fingerprint = fingerprint8(trimmed) };
    }
    if (containsIgnoreCase(trimmed, "-----BEGIN OPENSSH PRIVATE KEY-----")) {
        return .{ .label = "secret:ssh_private_key", .fingerprint = fingerprint8(trimmed) };
    }
    if (containsCloudCredentialJson(trimmed)) {
        return .{ .label = "secret:cloud_credentials_json", .fingerprint = fingerprint8(trimmed) };
    }
    if (looksLikeAwsAccessKey(trimmed)) {
        return .{ .label = "secret:aws_access_key", .fingerprint = fingerprint8(trimmed) };
    }
    if (looksLikeGithubToken(trimmed)) {
        return .{ .label = "secret:github_token", .fingerprint = fingerprint8(trimmed) };
    }
    if (looksLikeOpenAiKey(trimmed)) {
        return .{ .label = "secret:openai_api_key", .fingerprint = fingerprint8(trimmed) };
    }
    if (looksLikeAnthropicKey(trimmed)) {
        return .{ .label = "secret:anthropic_api_key", .fingerprint = fingerprint8(trimmed) };
    }
    if (looksLikeJwt(trimmed)) {
        return .{ .label = "secret:jwt", .fingerprint = fingerprint8(trimmed) };
    }
    if (looksHighEntropy(trimmed)) {
        return .{ .label = "secret:high_entropy", .fingerprint = fingerprint8(trimmed) };
    }
    return null;
}

pub fn formatEnvReplacement(buffer: []u8, name: []const u8, value: []const u8) ![]const u8 {
    const digest = fingerprint8(value);
    return try std.fmt.bufPrint(buffer, "[REDACTED:env:{s}:sha256:{s}]", .{ name, &digest });
}

fn formatReplacement(buffer: []u8, label: []const u8, digest: *const [8]u8) ![]const u8 {
    if (std.mem.startsWith(u8, label, "secret:")) {
        return try std.fmt.bufPrint(buffer, "[REDACTED:{s}:sha256:{s}]", .{ label, digest });
    }
    return try std.fmt.bufPrint(buffer, "[REDACTED:env:{s}:sha256:{s}]", .{ label, digest });
}

pub fn fingerprint8(value: []const u8) [8]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(value, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    var out: [8]u8 = undefined;
    @memcpy(&out, hex[0..8]);
    return out;
}

fn parseEnvAssignment(value: []const u8) ?EnvAssignment {
    const eq = std.mem.indexOfScalar(u8, value, '=') orelse return null;
    if (eq == 0) return null;
    const name = value[0..eq];
    for (name) |char| {
        if (!(std.ascii.isAlphanumeric(char) or char == '_')) return null;
    }
    return .{ .name = name, .value = value[eq + 1 ..] };
}

fn classifyEmbeddedAssignment(value: []const u8) ?RedactionMatch {
    var tokens = std.mem.tokenizeAny(u8, value, " \t\r\n");
    while (tokens.next()) |raw_token| {
        const token = trimCommandToken(raw_token);
        if (parseEnvAssignment(token)) |assignment| {
            if (isSecretEnvName(assignment.name)) {
                return .{ .label = assignment.name, .fingerprint = fingerprint8(assignment.value) };
            }
            if (classifySecretValue(assignment.value)) |match| return match;
        }
    }
    return null;
}

fn classifyEmbeddedSecretToken(value: []const u8) ?RedactionMatch {
    var tokens = std.mem.tokenizeAny(u8, value, " \t\r\n?&=|,;:\"'()[]{}<>");
    while (tokens.next()) |raw_token| {
        const token = std.mem.trim(u8, raw_token, ":");
        if (classifySecretValue(token)) |match| return match;
    }
    return null;
}

fn trimCommandToken(token: []const u8) []const u8 {
    var out = std.mem.trim(u8, token, "\"'");
    while (out.len > 0 and (out[out.len - 1] == ',' or out[out.len - 1] == ';')) {
        out = out[0 .. out.len - 1];
        out = std.mem.trim(u8, out, "\"'");
    }
    return out;
}

fn looksLikeAwsAccessKey(value: []const u8) bool {
    if (value.len != 20) return false;
    if (!(std.mem.startsWith(u8, value, "AKIA") or std.mem.startsWith(u8, value, "ASIA"))) return false;
    for (value[4..]) |char| {
        if (!std.ascii.isAlphanumeric(char)) return false;
    }
    return true;
}

fn looksLikeGithubToken(value: []const u8) bool {
    return ((std.mem.startsWith(u8, value, "ghp_") or
        std.mem.startsWith(u8, value, "gho_") or
        std.mem.startsWith(u8, value, "ghu_") or
        std.mem.startsWith(u8, value, "ghs_") or
        std.mem.startsWith(u8, value, "ghr_")) and value.len >= 20) or
        (std.mem.startsWith(u8, value, "github_pat_") and value.len >= 30);
}

fn looksLikeOpenAiKey(value: []const u8) bool {
    return std.mem.startsWith(u8, value, "sk-") and value.len >= 20;
}

fn looksLikeAnthropicKey(value: []const u8) bool {
    return std.mem.startsWith(u8, value, "sk-ant-") and value.len >= 24;
}

fn looksLikeJwt(value: []const u8) bool {
    var parts: usize = 0;
    var start: usize = 0;
    while (start <= value.len) {
        const dot = std.mem.indexOfScalarPos(u8, value, start, '.') orelse value.len;
        const part = value[start..dot];
        if (part.len < 8) return false;
        for (part) |char| {
            if (!(std.ascii.isAlphanumeric(char) or char == '-' or char == '_')) return false;
        }
        parts += 1;
        if (dot == value.len) break;
        start = dot + 1;
    }
    return parts == 3;
}

fn looksHighEntropy(value: []const u8) bool {
    if (value.len < 32 or value.len > 512) return false;
    if (std.mem.indexOfAny(u8, value, "/\\:") != null) return false;
    var classes: u8 = 0;
    var unique = [_]bool{false} ** 256;
    var unique_count: usize = 0;
    for (value) |char| {
        if (std.ascii.isUpper(char)) classes |= 1 else if (std.ascii.isLower(char)) classes |= 2 else if (std.ascii.isDigit(char)) classes |= 4 else if (char == '_' or char == '-' or char == '/' or char == '+' or char == '=') classes |= 8 else return false;
        if (!unique[char]) {
            unique[char] = true;
            unique_count += 1;
        }
    }
    return @popCount(classes) >= 3 and unique_count >= 16;
}

fn containsCloudCredentialJson(value: []const u8) bool {
    return (containsIgnoreCase(value, "\"type\"") and containsIgnoreCase(value, "\"service_account\"")) or
        containsIgnoreCase(value, "\"private_key\"") or
        containsIgnoreCase(value, "\"aws_access_key_id\"") or
        containsIgnoreCase(value, "\"client_email\"");
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return true;
    }
    return false;
}

fn matchesPatternIgnoreCase(pattern: []const u8, value: []const u8) bool {
    return globMatchIgnoreCase(pattern, 0, value, 0);
}

fn globMatchIgnoreCase(pattern: []const u8, pattern_index: usize, value: []const u8, value_index: usize) bool {
    var p = pattern_index;
    var v = value_index;
    while (p < pattern.len) {
        switch (pattern[p]) {
            '*' => {
                while (p + 1 < pattern.len and pattern[p + 1] == '*') p += 1;
                if (p + 1 == pattern.len) return true;
                var next = v;
                while (next <= value.len) : (next += 1) {
                    if (globMatchIgnoreCase(pattern, p + 1, value, next)) return true;
                }
                return false;
            },
            '?' => {
                if (v >= value.len) return false;
                p += 1;
                v += 1;
            },
            else => |char| {
                if (v >= value.len or std.ascii.toLower(value[v]) != std.ascii.toLower(char)) return false;
                p += 1;
                v += 1;
            },
        }
    }
    return v == value.len;
}

test "secret env name detection covers common variables" {
    try std.testing.expect(isSecretEnvName("GITHUB_TOKEN"));
    try std.testing.expect(isSecretEnvName("FAKE_GITHUB_TOKEN"));
    try std.testing.expect(isSecretEnvName("OPENAI_API_KEY"));
    try std.testing.expect(isSecretEnvName("SSH_AUTH_SOCK"));
    try std.testing.expect(!isSecretEnvName("PATH"));
}

test "secret value detection covers synthetic examples" {
    try std.testing.expect(classifySecretValue("-----BEGIN PRIVATE KEY-----\nFAKE\n-----END PRIVATE KEY-----") != null);
    try std.testing.expect(classifySecretValue("AKIAIOSFODNN7EXAMPLE") != null);
    try std.testing.expect(classifySecretValue("ghp_fakeSyntheticTokenValue1234567890") != null);
    try std.testing.expect(classifySecretValue("sk-fakeSyntheticOpenAIKey1234567890") != null);
    try std.testing.expect(classifySecretValue("sk-ant-fakeSyntheticAnthropicKey1234567890") != null);
    try std.testing.expect(classifySecretValue("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJmYWtlIn0.c2lnbmF0dXJl") != null);
    try std.testing.expect(classifySecretValue("Aa0Bb1Cc2Dd3Ee4Ff5Gg6Hh7Ii8Jj9Kk") != null);
    try std.testing.expect(classifySecretValue("{\"type\":\"service_account\",\"private_key\":\"FAKE\"}") != null);
    try std.testing.expect(classifySecretValue("/Users/fake/aegis/path/with/mixed/Chars123") == null);
}

test "redaction fingerprints are stable and do not include raw value" {
    var first: [256]u8 = undefined;
    var second: [256]u8 = undefined;
    const fake = "GITHUB_TOKEN=fake_secret_value";
    const a = redactStringBounded(fake, &first);
    const b = redactStringBounded(fake, &second);
    try std.testing.expectEqualStrings(a, b);
    try std.testing.expect(std.mem.indexOf(u8, a, "fake_secret_value") == null);
    try std.testing.expect(std.mem.startsWith(u8, a, "[REDACTED:env:GITHUB_TOKEN:sha256:"));
}

test "redaction catches embedded synthetic secret assignments in command text" {
    var buf: [256]u8 = undefined;
    const command = "/bin/echo OPENAI_API_KEY=sk-fakeSyntheticOpenAIKey1234567890";
    const redacted = redactStringBounded(command, &buf);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "sk-fakeSyntheticOpenAIKey") == null);
    try std.testing.expect(std.mem.startsWith(u8, redacted, "[REDACTED:env:OPENAI_API_KEY:sha256:"));
}

test "redaction covers synthetic policy url mcp and command contexts" {
    const cases = [_][]const u8{
        "env FAKE_GITHUB_TOKEN=ghp_fakeSyntheticTokenValue1234567890",
        "policy: api_key: sk-ant-fakeSyntheticAnthropicKey1234567890",
        "mcp args {\"OPENAI_API_KEY\":\"sk-fakeSyntheticOpenAIKey1234567890\"}",
        "url=https://example.invalid/?token=sk-fakeSyntheticOpenAIKey1234567890",
        "-----BEGIN PRIVATE KEY-----\nfake-secret-value\n-----END PRIVATE KEY-----",
        "{\"type\":\"service_account\",\"private_key\":\"fake-secret-value\",\"client_email\":\"fake@example.invalid\"}",
    };
    for (cases) |case| {
        var buf: [256]u8 = undefined;
        const redacted = redactStringBounded(case, &buf);
        try std.testing.expect(std.mem.indexOf(u8, redacted, "fakeSynthetic") == null);
        try std.testing.expect(std.mem.indexOf(u8, redacted, "fake-secret-value") == null);
        try std.testing.expect(std.mem.indexOf(u8, redacted, "[REDACTED:") != null);
    }
}
