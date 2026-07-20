pub const backend = @import("backend.zig");
pub const observe = @import("observe.zig");
pub const linux = @import("linux.zig");
pub const macos = @import("macos.zig");
pub const windows = @import("windows.zig");
pub const posture = @import("posture.zig");
pub const launch_authority = @import("launch_authority.zig");
pub const evidence = @import("evidence.zig");
pub const canary = @import("canary.zig");
pub const env_scrub = @import("env_scrub.zig");
pub const fd_scrub = @import("fd_scrub.zig");
pub const profile = @import("profile.zig");
pub const apply = @import("apply.zig");
pub const landlock = @import("landlock.zig");
pub const apply_posix = @import("apply_posix.zig");
pub const macos_profile = @import("macos_profile.zig");
pub const macos_seatbelt = @import("macos_seatbelt.zig");

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
    _ = env_scrub;
    _ = fd_scrub;
    _ = profile;
    _ = apply;
    _ = landlock;
    _ = apply_posix;
    _ = macos_profile;
    _ = macos_seatbelt;
}
