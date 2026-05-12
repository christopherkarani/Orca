const std = @import("std");
const evaluator = @import("evaluator.zig");

pub fn writeHuman(writer: anytype, evaluation: evaluator.SafetyEvaluation) !void {
    try writer.print("Decision: {s}\n", .{evaluation.decision.result.toString()});
    try writer.print("Explanation: {s}\n", .{evaluation.explanation});
    if (evaluation.findings.len > 0) {
        try writer.writeAll("Safety findings:\n");
        for (evaluation.findings) |finding| {
            try writer.print("  - {s}/{s}: {s}\n", .{ @tagName(finding.category), @tagName(finding.severity), finding.explanation });
        }
    }
    try writer.writeAll("No command was forwarded by the safety evaluator.\n");
}

test {
    _ = std;
}

