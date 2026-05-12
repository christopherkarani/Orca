pub fn requirePercent(value: f64) !void {
    if (value < 0 or value > 100) return error.InvalidPercent;
}

pub fn requireNonNegative(value: f64, err: anyerror) !void {
    if (value < 0) return err;
}

pub fn requireNonEmpty(value: []const u8, err: anyerror) !void {
    if (value.len == 0) return err;
}
