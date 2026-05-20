const std = @import("std");
const core = @import("orca_core");
const data_classification = @import("data_classification.zig");

pub const RedactionResult = struct {
    allocator: std.mem.Allocator,
    text: []u8,
    redaction_count: u32,
    redaction_required: bool,
    safe_to_persist: bool,
    status: data_classification.RedactionStatus,

    pub fn deinit(self: *RedactionResult) void {
        self.allocator.free(self.text);
        self.* = undefined;
    }
};

pub fn redactPayload(
    allocator: std.mem.Allocator,
    payload: []const u8,
    classes: []const data_classification.DataClass,
    coarse_geolocation: bool,
) !RedactionResult {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    var count: u32 = 0;
    var required = false;
    const safe_to_persist = true;
    const binary_like = looksBinary(payload);

    if (hasClass(classes, .video_stream) or hasClass(classes, .image_frame) or hasClass(classes, .audio_stream) or binary_like) {
        required = true;
        count += 1;
        try output.appendSlice(allocator, "{\"payload\":\"[REDACTED:raw-media-or-binary]\"}");
        return .{ .allocator = allocator, .text = try output.toOwnedSlice(allocator), .redaction_count = count, .redaction_required = required, .safe_to_persist = false, .status = .redacted };
    }

    if (hasClass(classes, .mission_plan)) {
        required = true;
        count += 1;
    }
    if (hasClass(classes, .geolocation) and coarse_geolocation) {
        required = true;
        count += 1;
    }
    if (hasClass(classes, .secret) or hasClass(classes, .credential)) {
        required = true;
        count += 1;
    }

    var tokens = std.mem.tokenizeAny(u8, payload, " \t\r\n,{}[]:\"'");
    var redacted_secret = false;
    while (tokens.next()) |token| {
        if (!std.mem.eql(u8, core.api.redactString(token), token)) {
            redacted_secret = true;
            break;
        }
    }

    var buffer: [2048]u8 = undefined;
    const bounded = if (payload.len > buffer.len) payload[0..buffer.len] else payload;
    var redacted = core.api.redactStringBounded(bounded, &buffer);
    if (redacted.ptr == bounded.ptr and redacted_secret) {
        redacted = "[REDACTED:secret]";
    }

    if (coarse_geolocation and hasClass(classes, .geolocation)) {
        redacted = "[REDACTED:coarse_geolocation]";
    } else if (hasClass(classes, .mission_plan)) {
        redacted = "[REDACTED:mission_plan_summary]";
    }

    try output.appendSlice(allocator, redacted);
    if (payload.len > bounded.len) try output.appendSlice(allocator, "[TRUNCATED]");
    return .{
        .allocator = allocator,
        .text = try output.toOwnedSlice(allocator),
        .redaction_count = count,
        .redaction_required = required,
        .safe_to_persist = safe_to_persist and !hasClass(classes, .secret) and !hasClass(classes, .credential),
        .status = if (required) if (coarse_geolocation and hasClass(classes, .geolocation)) .coarsened else .redacted else .none,
    };
}

pub fn redactQuery(allocator: std.mem.Allocator, query: []const u8) ![]u8 {
    if (query.len == 0) return allocator.dupe(u8, "");
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var parts = std.mem.splitScalar(u8, query, '&');
    var first = true;
    while (parts.next()) |part| {
        if (!first) try out.append(allocator, '&');
        first = false;
        const eq = std.mem.indexOfScalar(u8, part, '=') orelse {
            try out.appendSlice(allocator, "[REDACTED]");
            continue;
        };
        const name = part[0..eq];
        const value = part[eq + 1 ..];
        try out.appendSlice(allocator, name);
        try out.append(allocator, '=');
        if (isSecretName(name) or !std.mem.eql(u8, core.api.redactString(value), value)) {
            try out.appendSlice(allocator, "[REDACTED]");
        } else if (value.len > 64) {
            try out.appendSlice(allocator, "[REDACTED:long-value]");
        } else {
            try out.appendSlice(allocator, value);
        }
    }
    return try out.toOwnedSlice(allocator);
}

pub fn hasClass(classes: []const data_classification.DataClass, class: data_classification.DataClass) bool {
    for (classes) |candidate| {
        if (candidate == class) return true;
    }
    return false;
}

fn isSecretName(name: []const u8) bool {
    return data_classification.containsAny(name, &.{ "token", "secret", "key", "password", "authorization", "credential" });
}

fn looksBinary(payload: []const u8) bool {
    if (payload.len == 0) return false;
    var control: usize = 0;
    for (payload) |byte| {
        if (byte == 0) return true;
        if (byte < 0x09 or (byte > 0x0d and byte < 0x20)) control += 1;
    }
    return control * 8 > payload.len;
}

test "redacts fake secrets and query secrets" {
    var result = try redactPayload(std.testing.allocator, "{\"api_key\":\"sk-fakeSyntheticOpenAIKey1234567890\"}", &.{.credential}, false);
    defer result.deinit();
    try std.testing.expect(std.mem.indexOf(u8, result.text, "sk-fake") == null);
    try std.testing.expect(result.redaction_required);

    const query = try redactQuery(std.testing.allocator, "token=fake_secret_value&mode=test");
    defer std.testing.allocator.free(query);
    try std.testing.expect(std.mem.indexOf(u8, query, "fake_secret_value") == null);
}
