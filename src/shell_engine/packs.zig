//! MVP destructive + safe pack intent for in-process Zig evaluation.
//! Rule ids intentionally mirror Rust pack ids where feasible for corpus parity.

const std = @import("std");
const tokenize = @import("tokenize.zig");
const Severity = @import("types.zig").Severity;

pub const Hit = struct {
    pack_id: []const u8,
    pattern_name: []const u8,
    severity: Severity,
    reason: []const u8,
    explanation: ?[]const u8 = null,
};

pub fn isSafeCommand(command: []const u8) bool {
    const trimmed = std.mem.trim(u8, command, " \t\r\n");
    // Fast string prefixes for common read-only tools.
    const safes = [_][]const u8{
        "git status",
        "git log",
        "git diff",
        "git show",
        "git branch",
        "git remote -v",
        "git rev-parse",
        "ls ",
        "ls\t",
        "pwd",
        "echo ",
        "echo\t",
        "cat ",
        "head ",
        "tail ",
        "which ",
        "whoami",
        "uname",
        "true",
        "false",
        "test ",
        "printf ",
    };
    // Exact safe singles
    if (std.mem.eql(u8, trimmed, "ls") or
        std.mem.eql(u8, trimmed, "pwd") or
        std.mem.eql(u8, trimmed, "git status") or
        std.mem.eql(u8, trimmed, "git log") or
        std.mem.eql(u8, trimmed, "echo") or
        std.mem.eql(u8, trimmed, "whoami") or
        std.mem.eql(u8, trimmed, "uname") or
        std.mem.eql(u8, trimmed, "true") or
        std.mem.eql(u8, trimmed, "false"))
    {
        return true;
    }
    for (safes) |s| {
        if (std.mem.startsWith(u8, trimmed, s)) {
            // Don't treat "git status --porcelain" as unsafe; still safe.
            // Block if later tokens introduce destructive ops (handled by destructive match first
            // only when we don't short-circuit — so keep safe narrow).
            if (std.mem.startsWith(u8, s, "git ")) {
                // git branch -D is destructive; exclude force-delete forms.
                if (std.mem.indexOf(u8, trimmed, " -D") != null) return false;
                if (std.mem.indexOf(u8, trimmed, " --delete") != null and std.mem.indexOf(u8, trimmed, " -D") != null) return false;
                if (std.mem.indexOf(u8, trimmed, " reset ") != null) return false;
                if (std.mem.indexOf(u8, trimmed, " clean ") != null) return false;
                if (std.mem.indexOf(u8, trimmed, " push ") != null) return false;
                if (std.mem.indexOf(u8, trimmed, " stash drop") != null) return false;
                if (std.mem.indexOf(u8, trimmed, " stash clear") != null) return false;
            }
            if (std.mem.eql(u8, s, "cat ") and looksLikeCredentialPath(trimmed)) return false;
            return true;
        }
    }
    return false;
}

fn looksLikeCredentialPath(command: []const u8) bool {
    const needles = [_][]const u8{ ".env", "/.ssh/", "id_rsa", "credentials", ".aws/", ".gnupg" };
    for (needles) |n| {
        if (std.mem.indexOf(u8, command, n) != null) return true;
    }
    return false;
}

pub fn matchDestructive(command: []const u8) ?Hit {
    const trimmed = std.mem.trim(u8, command, " \t\r\n");

    // Compound / string-level checks first (before argv).
    if (matchFilesystemString(trimmed)) |h| return h;
    if (matchGitString(trimmed)) |h| return h;
    if (matchSystemString(trimmed)) |h| return h;
    if (matchPermissionsString(trimmed)) |h| return h;
    if (matchServicesString(trimmed)) |h| return h;

    // Argv structured checks (allocator-free via stack buffer for short cmds).
    var stack_buf: [64][]const u8 = undefined;
    var arg_count: usize = 0;
    var i: usize = 0;
    while (i < trimmed.len and arg_count < stack_buf.len) {
        while (i < trimmed.len and std.ascii.isWhitespace(trimmed[i])) : (i += 1) {}
        if (i >= trimmed.len) break;
        const start = i;
        while (i < trimmed.len and !std.ascii.isWhitespace(trimmed[i])) : (i += 1) {}
        stack_buf[arg_count] = trimmed[start..i];
        arg_count += 1;
    }
    if (arg_count == 0) return null;
    const args = stack_buf[0..arg_count];
    if (matchFilesystemArgv(args)) |h| return h;
    if (matchGitArgv(args)) |h| return h;
    if (matchSystemArgv(args)) |h| return h;
    return null;
}

fn flagBundleHas(flag: []const u8, want_r: *bool, want_f: *bool) void {
    if (flag.len < 2 or flag[0] != '-') return;
    if (std.mem.eql(u8, flag, "--recursive")) {
        want_r.* = true;
        return;
    }
    if (std.mem.eql(u8, flag, "--force")) {
        want_f.* = true;
        return;
    }
    if (flag.len >= 2 and flag[1] != '-') {
        for (flag[1..]) |c| {
            if (c == 'r' or c == 'R') want_r.* = true;
            if (c == 'f') want_f.* = true;
        }
    }
}

fn isRootOrHomeTarget(path: []const u8) bool {
    if (path.len == 0) return false;
    if (std.mem.eql(u8, path, "/") or std.mem.eql(u8, path, "~")) return true;
    if (std.mem.startsWith(u8, path, "$HOME") or std.mem.startsWith(u8, path, "${HOME}")) return true;
    if (std.mem.eql(u8, path, "/.") or std.mem.eql(u8, path, "/..")) return true;
    return false;
}

fn isSensitivePath(path: []const u8) bool {
    if (isRootOrHomeTarget(path)) return true;
    const prefixes = [_][]const u8{ "/etc", "/usr", "/bin", "/sbin", "/root", "/boot", "/lib", "/var", "/home", "/sys", "/proc", "/dev", "/opt" };
    for (prefixes) |p| {
        if (std.mem.eql(u8, path, p)) return true;
        if (path.len > p.len and std.mem.startsWith(u8, path, p) and path[p.len] == '/') return true;
    }
    return false;
}

fn matchFilesystemString(cmd: []const u8) ?Hit {
    // find -delete
    if (std.mem.indexOf(u8, cmd, "find ") != null and std.mem.indexOf(u8, cmd, "-delete") != null) {
        if (std.mem.indexOf(u8, cmd, "find /") != null or std.mem.indexOf(u8, cmd, "find ~") != null or
            std.mem.indexOf(u8, cmd, "find $HOME") != null or std.mem.indexOf(u8, cmd, "find /etc") != null)
        {
            return hit("core.filesystem", "find-delete-root-home", .critical, "find -delete on a sensitive path is EXTREMELY DANGEROUS.");
        }
        return hit("core.filesystem", "find-delete-general", .high, "find -delete is destructive and requires human approval.");
    }
    if (containsWord(cmd, "shred")) {
        return hit("core.filesystem", "shred-general", .high, "shred destroys file content beyond recovery and requires human approval.");
    }
    if (std.mem.indexOf(u8, cmd, "truncate") != null and (std.mem.indexOf(u8, cmd, "-s 0") != null or std.mem.indexOf(u8, cmd, "--size=0") != null)) {
        return hit("core.filesystem", "truncate-zero-general", .high, "truncate -s 0 is destructive and requires human approval.");
    }
    if (std.mem.indexOf(u8, cmd, "tar ") != null and std.mem.indexOf(u8, cmd, "--remove-files") != null) {
        return hit("core.filesystem", "tar-remove-files-general", .high, "tar --remove-files deletes source paths after archiving.");
    }
    return null;
}

fn matchFilesystemArgv(args: []const []const u8) ?Hit {
    const exe = tokenize.basename(args[0]);
    if (std.mem.eql(u8, exe, "rm") or std.mem.eql(u8, exe, "rm.exe")) {
        var want_r = false;
        var want_f = false;
        var targets: usize = 0;
        var first_target: ?[]const u8 = null;
        for (args[1..]) |arg| {
            if (std.mem.startsWith(u8, arg, "-")) {
                flagBundleHas(arg, &want_r, &want_f);
            } else {
                if (first_target == null) first_target = arg;
                targets += 1;
            }
        }
        if (want_r and want_f) {
            if (first_target) |t| {
                if (isRootOrHomeTarget(t) or isSensitivePath(t)) {
                    return hit("core.filesystem", "rm-rf-root-home", .critical, "rm -rf on root or home paths is EXTREMELY DANGEROUS.");
                }
            }
            return hit("core.filesystem", "rm-rf-general", .high, "rm -rf is destructive and requires human approval.");
        }
    }
    if (std.mem.eql(u8, exe, "unlink")) {
        if (args.len >= 2) {
            if (isSensitivePath(args[1])) {
                return hit("core.filesystem", "unlink-root-home", .critical, "unlink on a sensitive path is EXTREMELY DANGEROUS.");
            }
            return hit("core.filesystem", "unlink-general", .high, "unlink is destructive and requires human approval.");
        }
    }
    if (std.mem.eql(u8, exe, "dd")) {
        for (args[1..]) |arg| {
            if (std.mem.startsWith(u8, arg, "of=/dev/")) {
                return hit("system.disk", "dd-device", .critical, "dd to a block device will OVERWRITE all data on that device.");
            }
            if (std.mem.startsWith(u8, arg, "of=/") or std.mem.startsWith(u8, arg, "of=~")) {
                return hit("core.filesystem", "dd-overwrite-general", .high, "dd with of=<file> overwrites file contents.");
            }
        }
    }
    if (std.mem.eql(u8, exe, "mv")) {
        for (args[1..]) |arg| {
            if (std.mem.startsWith(u8, arg, "-")) continue;
            if (isSensitivePath(arg)) {
                return hit("core.filesystem", "mv-sensitive-source-root-home", .critical, "mv touching a sensitive system or home path is EXTREMELY DANGEROUS.");
            }
        }
    }
    return null;
}

fn matchGitString(cmd: []const u8) ?Hit {
    // Path-prefixed git still matches via contains.
    if (!containsWord(cmd, "git")) return null;
    return null; // argv path handles most; string used for compound later
}

fn matchGitArgv(args: []const []const u8) ?Hit {
    const exe = tokenize.basename(args[0]);
    if (!std.mem.eql(u8, exe, "git") and !std.mem.eql(u8, exe, "git.exe")) return null;
    if (args.len < 2) return null;

    // Find subcommand (skip global options like -C).
    var idx: usize = 1;
    while (idx < args.len and std.mem.startsWith(u8, args[idx], "-")) {
        // -C takes a path argument
        if (std.mem.eql(u8, args[idx], "-C") or std.mem.eql(u8, args[idx], "--git-dir") or std.mem.eql(u8, args[idx], "--work-tree")) {
            idx += 2;
            continue;
        }
        idx += 1;
    }
    if (idx >= args.len) return null;
    const sub = args[idx];
    const rest = args[idx + 1 ..];

    if (std.mem.eql(u8, sub, "reset")) {
        for (rest) |a| {
            if (std.mem.eql(u8, a, "--hard")) {
                return hit("core.git", "reset-hard", .critical, "git reset --hard destroys uncommitted changes.");
            }
        }
    }
    if (std.mem.eql(u8, sub, "clean")) {
        var has_f = false;
        var has_d = false;
        var dry = false;
        for (rest) |a| {
            if (std.mem.eql(u8, a, "--dry-run") or std.mem.eql(u8, a, "-n")) dry = true;
            if (std.mem.startsWith(u8, a, "-") and a.len >= 2 and a[1] != '-') {
                for (a[1..]) |c| {
                    if (c == 'f') has_f = true;
                    if (c == 'd') has_d = true;
                    if (c == 'n') dry = true;
                    if (c == 'x') has_f = true; // -fdx still force
                }
            }
            if (std.mem.eql(u8, a, "--force")) has_f = true;
        }
        if (has_f and !dry) {
            return hit("core.git", "clean-force", .high, "git clean with force removes untracked files permanently.");
        }
    }
    if (std.mem.eql(u8, sub, "push")) {
        for (rest) |a| {
            if (std.mem.eql(u8, a, "--force") or std.mem.eql(u8, a, "--force-with-lease") or std.mem.eql(u8, a, "-f")) {
                if (std.mem.eql(u8, a, "--force") or std.mem.eql(u8, a, "--force-with-lease")) {
                    return hit("core.git", "push-force-long", .critical, "git push --force rewrites remote history.");
                }
                return hit("core.git", "push-force-short", .critical, "git push -f rewrites remote history.");
            }
        }
    }
    if (std.mem.eql(u8, sub, "stash")) {
        if (rest.len >= 1 and std.mem.eql(u8, rest[0], "drop")) {
            return hit("core.git", "stash-drop", .high, "git stash drop discards a stash permanently.");
        }
        if (rest.len >= 1 and std.mem.eql(u8, rest[0], "clear")) {
            return hit("core.git", "stash-clear", .high, "git stash clear drops all stashes.");
        }
    }
    if (std.mem.eql(u8, sub, "branch")) {
        for (rest) |a| {
            if (std.mem.eql(u8, a, "-D")) {
                return hit("core.git", "branch-force-delete", .high, "git branch -D force deletes a branch.");
            }
        }
    }
    if (std.mem.eql(u8, sub, "checkout")) {
        // git checkout -- <path> discards changes
        for (rest, 0..) |a, i| {
            if (std.mem.eql(u8, a, "--") and i + 1 < rest.len) {
                return hit("core.git", "checkout-discard", .high, "git checkout -- discards uncommitted changes permanently.");
            }
        }
    }
    if (std.mem.eql(u8, sub, "restore")) {
        var staged_only = false;
        var worktree = false;
        for (rest) |a| {
            if (std.mem.eql(u8, a, "--staged") or std.mem.eql(u8, a, "-S")) staged_only = true;
            if (std.mem.eql(u8, a, "--worktree") or std.mem.eql(u8, a, "-W")) worktree = true;
        }
        if (!staged_only or worktree) {
            // restore without --staged (or with worktree) can discard WT changes — strict_git intent
            if (rest.len > 0) {
                return hit("strict_git", "restore-worktree", .high, "git restore can discard working tree changes.");
            }
        }
    }
    if (std.mem.eql(u8, sub, "rebase") and rest.len > 0) {
        for (rest) |a| {
            if (std.mem.eql(u8, a, "--abort")) continue;
            if (std.mem.eql(u8, a, "-i") or std.mem.eql(u8, a, "--interactive")) {
                return hit("strict_git", "rebase-interactive", .medium, "interactive rebase rewrites history.");
            }
        }
    }
    return null;
}

fn matchSystemString(cmd: []const u8) ?Hit {
    if (containsWord(cmd, "mkfs") or std.mem.indexOf(u8, cmd, "mkfs.") != null) {
        return hit("system.disk", "mkfs", .critical, "mkfs formats a partition/device and ERASES all existing data.");
    }
    if (containsWord(cmd, "mkswap")) {
        return hit("system.disk", "mkswap", .critical, "mkswap formats a partition as a swap area, ERASING any existing data.");
    }
    if (containsWord(cmd, "wipefs")) {
        return hit("system.disk", "wipefs", .high, "wipefs removes filesystem signatures.");
    }
    if (containsWord(cmd, "fdisk") and std.mem.indexOf(u8, cmd, "/dev/") != null and std.mem.indexOf(u8, cmd, "-l") == null) {
        return hit("system.disk", "fdisk-edit", .high, "fdisk can modify partition tables and cause data loss.");
    }
    if (containsWord(cmd, "parted") and std.mem.indexOf(u8, cmd, "/dev/") != null) {
        return hit("system.disk", "parted-modify", .high, "parted can modify partition tables and cause data loss.");
    }
    const lvm = [_][]const u8{ "pvremove", "vgremove", "lvremove", "vgreduce", "lvreduce", "pvmove" };
    for (lvm) |w| {
        if (containsWord(cmd, w)) {
            return hit("system.disk", w, .critical, "LVM destructive operation can erase volumes.");
        }
    }
    if (containsWord(cmd, "mdadm") and (std.mem.indexOf(u8, cmd, "--zero-superblock") != null or
        std.mem.indexOf(u8, cmd, "--create") != null or std.mem.indexOf(u8, cmd, " -C") != null))
    {
        return hit("system.disk", "mdadm-create", .critical, "mdadm create/zero-superblock erases RAID metadata or devices.");
    }
    if (std.mem.indexOf(u8, cmd, "btrfs") != null and std.mem.indexOf(u8, cmd, "subvolume delete") != null) {
        return hit("system.disk", "btrfs-subvolume-delete", .critical, "btrfs subvolume delete permanently removes a subvolume.");
    }
    if (containsWord(cmd, "dmsetup") and std.mem.indexOf(u8, cmd, "remove_all") != null) {
        return hit("system.disk", "dmsetup-remove-all", .critical, "dmsetup remove_all removes ALL device-mapper devices.");
    }
    return null;
}

fn matchSystemArgv(args: []const []const u8) ?Hit {
    const exe = tokenize.basename(args[0]);
    if (std.mem.startsWith(u8, exe, "mkfs")) {
        return hit("system.disk", "mkfs", .critical, "mkfs formats a partition/device and ERASES all existing data.");
    }
    if (std.mem.eql(u8, exe, "mkswap")) {
        return hit("system.disk", "mkswap", .critical, "mkswap formats a partition as a swap area.");
    }
    return null;
}

fn matchPermissionsString(cmd: []const u8) ?Hit {
    if (containsWord(cmd, "chmod") and (std.mem.indexOf(u8, cmd, " 777") != null or std.mem.indexOf(u8, cmd, "777 ") != null or std.mem.endsWith(u8, cmd, "777"))) {
        return hit("system.permissions", "chmod-world-writable", .high, "chmod 777 makes files world-writable.");
    }
    if (containsWord(cmd, "chown") and std.mem.indexOf(u8, cmd, "-R") != null and (std.mem.indexOf(u8, cmd, " /") != null or std.mem.endsWith(u8, cmd, " /"))) {
        return hit("system.permissions", "chown-recursive-root", .high, "recursive chown on system paths is dangerous.");
    }
    if (containsWord(cmd, "sudo") or containsWord(cmd, "doas")) {
        return hit("system.permissions", "privilege-escalation", .critical, "privilege escalation via sudo/doas requires human approval.");
    }
    return null;
}

fn matchServicesString(cmd: []const u8) ?Hit {
    if (containsWord(cmd, "systemctl") and (std.mem.indexOf(u8, cmd, " disable ") != null or std.mem.indexOf(u8, cmd, " stop ") != null or
        std.mem.indexOf(u8, cmd, " mask ") != null))
    {
        return hit("system.services", "systemctl-destructive", .high, "systemctl stop/disable/mask can disrupt services.");
    }
    if (containsWord(cmd, "service") and (std.mem.indexOf(u8, cmd, " stop") != null or std.mem.indexOf(u8, cmd, " remove") != null)) {
        return hit("system.services", "service-stop", .medium, "service stop/remove can disrupt services.");
    }
    return null;
}

fn containsWord(hay: []const u8, word: []const u8) bool {
    if (hay.len < word.len) return false;
    var i: usize = 0;
    while (i + word.len <= hay.len) : (i += 1) {
        if (std.mem.eql(u8, hay[i .. i + word.len], word)) {
            const before_ok = i == 0 or !isWordChar(hay[i - 1]);
            const after_ok = i + word.len == hay.len or !isWordChar(hay[i + word.len]);
            if (before_ok and after_ok) return true;
        }
    }
    return false;
}

fn isWordChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '-' or c == '.';
}

fn hit(pack_id: []const u8, pattern_name: []const u8, severity: Severity, reason: []const u8) Hit {
    return .{
        .pack_id = pack_id,
        .pattern_name = pattern_name,
        .severity = severity,
        .reason = reason,
    };
}

test "rm -rf general and root" {
    try std.testing.expect(matchDestructive("rm -rf ./build") != null);
    try std.testing.expect(matchDestructive("rm -rf /").?.severity == .critical);
    try std.testing.expect(matchDestructive("git status") == null);
}

test "git destructive" {
    try std.testing.expectEqualStrings("reset-hard", matchDestructive("git reset --hard").?.pattern_name);
    try std.testing.expectEqualStrings("push-force-long", matchDestructive("git push --force origin main").?.pattern_name);
}
