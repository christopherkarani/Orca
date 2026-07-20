pub const backend = @import("backend.zig");
pub const observe = @import("observe.zig");
pub const linux = @import("linux.zig");
pub const macos = @import("macos.zig");
pub const windows = @import("windows.zig");
pub const posture = @import("posture.zig");
pub const launch_authority = @import("launch_authority.zig");
pub const evidence = @import("evidence.zig");
pub const canary = @import("canary.zig");

pub const phase = "02-repo-bootstrap";

test {
    _ = backend;
    _ = observe;
    _ = linux;
    _ = macos;
    _ = windows;
    _ = posture;
    _ = launch_authority;
    _ = evidence;
    _ = canary;
}