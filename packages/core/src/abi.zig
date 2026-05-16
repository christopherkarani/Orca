const std = @import("std");
const aegis = @import("aegis");

pub const stability = "experimental";

pub const documentation =
    \\Aegis Core C ABI skeleton status: experimental, not stable v1.
    \\
    \\Exported functions reserve names for future bindings but do not provide a complete mobile or embedded binding.
    \\Callers own all input and output buffers. Aegis never frees caller memory.
    \\String inputs are UTF-8 byte slices passed as pointer plus length and must be no larger than Aegis Core runtime limits.
    \\String outputs are written into caller-provided buffers; functions return -2 when the output buffer is too small.
    \\Return convention: 0 success, negative values for invalid arguments, bounds failures, or unsupported skeleton behavior.
    \\This ABI does not expose real drone hardware, MAVLink, PX4, ArduPilot, or real-flight command enforcement.
;

pub export fn aegis_core_version(output_ptr: ?[*]u8, output_len: usize, written_ptr: ?*usize) c_int {
    return writeOutput("1.1.0-core-experimental", output_ptr, output_len, written_ptr);
}

pub export fn aegis_core_redact(input_ptr: ?[*]const u8, input_len: usize, output_ptr: ?[*]u8, output_len: usize, written_ptr: ?*usize) c_int {
    if (input_len > aegis.core.limits.max_event_field_len) return -3;
    if (input_len > 0 and input_ptr == null) return -1;
    const input = if (input_len == 0) "" else input_ptr.?[0..input_len];
    var buffer: [256]u8 = undefined;
    const redacted = aegis.audit.redact_bridge.redactStringBounded(input, &buffer);
    return writeOutput(redacted, output_ptr, output_len, written_ptr);
}

pub export fn aegis_core_evaluate_policy(_: [*]const u8, _: usize, _: [*]const u8, _: usize, _: [*]u8, _: usize, _: *usize) c_int {
    return -9;
}

pub export fn aegis_core_append_audit_event(_: [*]const u8, _: usize, _: [*]const u8, _: usize, _: [*]u8, _: usize, _: *usize) c_int {
    return -9;
}

fn writeOutput(value: []const u8, output_ptr: ?[*]u8, output_len: usize, written_ptr: ?*usize) c_int {
    const written = written_ptr orelse return -1;
    written.* = 0;
    if (value.len > 0 and output_ptr == null) return -1;
    if (output_len < value.len) return -2;
    if (value.len > 0) @memcpy(output_ptr.?[0..value.len], value);
    written.* = value.len;
    return 0;
}

test "experimental ABI redaction writes caller-owned output" {
    const input = "OPENAI_API_KEY=fake_secret_value_phase24";
    var output: [128]u8 = undefined;
    var written: usize = 0;
    try std.testing.expectEqual(@as(c_int, 0), aegis_core_redact(input, input.len, &output, output.len, &written));
    try std.testing.expect(std.mem.indexOf(u8, output[0..written], "fake_secret_value_phase24") == null);
}

test "experimental ABI rejects null caller buffers before slicing" {
    const input = "secret";
    var output: [64]u8 = undefined;
    var written: usize = 99;

    try std.testing.expectEqual(@as(c_int, -1), aegis_core_version(null, output.len, &written));
    try std.testing.expectEqual(@as(usize, 0), written);
    try std.testing.expectEqual(@as(c_int, -1), aegis_core_version(&output, output.len, null));

    written = 99;
    try std.testing.expectEqual(@as(c_int, -1), aegis_core_redact(null, input.len, &output, output.len, &written));
    try std.testing.expectEqual(@as(usize, 99), written);
    try std.testing.expectEqual(@as(c_int, -1), aegis_core_redact(input, input.len, null, output.len, &written));
    try std.testing.expectEqual(@as(usize, 0), written);

    try std.testing.expectEqual(@as(c_int, 0), aegis_core_redact(null, 0, &output, output.len, &written));
    try std.testing.expectEqual(@as(usize, 0), written);
}
