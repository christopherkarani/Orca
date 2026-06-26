/// Orca CLI design system and rich-output rendering (`tui`).
///
/// - `theme` — palette, color-capability detection, semantic tokens.
/// - `render` — linear rich-output primitives (panel, table, badge, meter, …).
/// - `prompt` — libvaxis-backed interactive widgets (select, multiSelect).
/// - `spinner` — libvaxis-aware spinner.
/// - `reasons` — human-readable policy reason + safe-alternative helpers.
pub const theme = @import("theme.zig");
pub const render = @import("render.zig");
pub const prompt = @import("prompt.zig");
pub const reasons = @import("reasons.zig");

test {
    _ = theme;
    _ = render;
    _ = prompt;
    _ = reasons;
}
