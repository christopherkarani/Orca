const std = @import("std");
const builtin = @import("builtin");

const core = @import("../core/mod.zig");
const core_api = @import("../core/api.zig");
const intercept = @import("../intercept/mod.zig");
const policy = @import("../policy/mod.zig");
const sandbox = @import("../sandbox/mod.zig");
const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");

const RunOptions = struct {
    workspace: ?[]const u8 = null,
    mode: core.types.Mode = .observe,
    mode_explicit: bool = false,
    policy_path: ?[]const u8 = null,
    session_name: ?[]const u8 = null,
    no_secrets: bool = false,
    inherit_env: bool = false,
    no_network: bool = false,
    network_mode: ?policy.schema.NetworkMode = null,
    allow_network_values: [32][]const u8 = undefined,
    allow_network_count: usize = 0,
    required_backend_values: [16]sandbox.backend.Feature = undefined,
    required_backend_count: usize = 0,
    command_argv: []const []const u8 = &.{},

    fn allowNetwork(self: *const RunOptions) []const []const u8 {
        return self.allow_network_values[0..self.allow_network_count];
    }

    fn requiredBackendFeatures(self: *const RunOptions) []const sandbox.backend.Feature {
        return self.required_backend_values[0..self.required_backend_count];
    }
};

pub fn command(argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    return commandWithStdio(argv, stdout, stderr, .inherit, true);
}

fn commandWithStdio(argv: []const []const u8, stdout: anytype, stderr: anytype, stdio: core.supervisor.StdioBehavior, audit_enabled: bool) !u8 {
    const options = parseOptions(argv, stdout, stderr) catch |err| switch (err) {
        error.HelpShown => return exit_codes.success,
        error.Usage => return exit_codes.usage,
        else => return err,
    };

    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const workspace_root_for_policy = core.supervisor.resolveWorkspaceRoot(allocator, options.workspace, ".") catch |err| switch (err) {
        error.FileNotFound => {
            try stderr.print("orca run: workspace not found: {s}\n", .{options.workspace orelse "."});
            return exit_codes.general;
        },
        else => return err,
    };
    defer allocator.free(workspace_root_for_policy);

    var loaded_policy = core_api.discoverPolicy(allocator, options.policy_path, workspace_root_for_policy) catch |err| {
        try stderr.print("orca run: invalid policy: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer loaded_policy.deinit();
    const effective_policy_mode = if (options.mode_explicit) coreModeToPolicyMode(options.mode) else loaded_policy.policy.mode;
    const session_mode = effective_policy_mode.toCoreMode();

    try applyNetworkOverlay(allocator, &loaded_policy.policy, options);

    var filtered_env = intercept.env.filterCurrent(allocator, &loaded_policy.policy, effective_policy_mode, .{
        .no_secrets = options.no_secrets,
        .inherit_env = options.inherit_env,
    }) catch |err| switch (err) {
        error.InheritEnvDenied => {
            try stderr.writeAll("orca run: --inherit-env is not allowed by the selected policy/mode.\n");
            return exit_codes.general;
        },
        else => {
            try stderr.print("orca run: failed to filter environment: {s}\n", .{@errorName(err)});
            return exit_codes.general;
        },
    };
    defer filtered_env.deinit();
    try installNetworkEnvironment(allocator, &filtered_env.env_map, loaded_policy.policy.network);
    const backend_report = sandbox.backend.detect(core.platform.detectOs());
    try installBackendEnvironment(&filtered_env.env_map, backend_report);

    const StartPrinter = struct {
        writer: @TypeOf(stdout),

        pub fn print(context: *anyopaque, session: core.session.Session) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            try printSessionStart(self.writer, session);
            try flushIfSupported(self.writer);
        }
    };

    var start_printer: StartPrinter = .{ .writer = stdout };
    const AuditContext = struct {
        allocator: std.mem.Allocator,
        writer: ?core_api.AuditWriter = null,
        session: ?core.session.Session = null,
        workspace_root_owned: ?[]const u8 = null,

        pub fn init(context: *anyopaque, session: core.session.Session) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.session = session;
            self.workspace_root_owned = try self.allocator.dupe(u8, session.workspace_root);
            self.writer = try core_api.createAuditWriter(self.allocator, session);
        }

        pub fn append(context: *anyopaque, ev: core.event.Event) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            try core_api.appendAuditEvent(&self.writer.?, ev);
        }

        pub fn deinit(self: *@This()) void {
            if (self.writer) |*writer| writer.deinit();
            self.writer = null;
            self.session = null;
            if (self.workspace_root_owned) |root| self.allocator.free(root);
            self.workspace_root_owned = null;
        }
    };
    var audit_context: AuditContext = .{ .allocator = allocator };
    defer audit_context.deinit();

    var session_approvals = intercept.approvals.SessionApprovals.init(allocator);
    defer session_approvals.deinit();

    const CommandGuardContext = struct {
        allocator: std.mem.Allocator,
        selected_policy: *const policy.schema.Policy,
        effective_mode: policy.schema.Mode,
        command_argv: []const []const u8,
        env_map: *std.process.EnvMap,
        audit_context: *AuditContext,
        approvals: *intercept.approvals.SessionApprovals,
        backend_report: sandbox.backend.ReportSet,
        required_backend_features: []const sandbox.backend.Feature,
        stderr: @TypeOf(stderr),

        pub fn beforeProcessLaunch(context: *anyopaque, session: core.session.Session) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            try self.installShims(session);
            try self.auditBackendCapability(session);
            if (self.backend_report.firstMissingRequired(self.required_backend_features)) |missing| {
                try self.auditBackendRequirementDenied(session, missing);
                return error.BackendRequirementUnavailable;
            }
            try self.auditNetworkStartupEvents(session);
            const display = try intercept.commands.displayArgvAlloc(self.allocator, self.command_argv);
            defer self.allocator.free(display);

            try self.auditCommandEvent(session, .command_attempt, display, null);

            var command_decision = try intercept.commands.evaluate(self.allocator, self.selected_policy, self.effective_mode, self.command_argv);
            defer command_decision.deinit(self.allocator);

            var final_decision = command_decision.decision;
            var approval_reason: ?[]const u8 = null;
            defer if (approval_reason) |reason| self.allocator.free(reason);
            const already_approved = self.approvals.contains(display);
            if (already_approved and final_decision.result == .ask) {
                approval_reason = try std.fmt.allocPrint(self.allocator, "session approval matched command: {s}", .{display});
                final_decision = .{
                    .result = .allow,
                    .reason = approval_reason.?,
                    .risk_score = command_decision.decision.risk_score,
                    .ci_may_proceed = true,
                };
            } else if (final_decision.result == .ask) {
                try self.auditCommandEvent(session, .command_approval_requested, display, final_decision);
                const choice = try self.resolveApproval(command_decision, display);
                switch (choice) {
                    .allow_once, .allow_session => {
                        if (choice == .allow_session) try self.approvals.allowForSession(display, command_decision.decision.reason);
                        try intercept.commands.appendApprovalHashEnv(
                            self.allocator,
                            self.env_map,
                            if (choice == .allow_session) intercept.commands.approved_session_env else intercept.commands.approved_once_env,
                            display,
                        );
                        approval_reason = try std.fmt.allocPrint(self.allocator, "user approved command {s}", .{if (choice == .allow_session) "for this session" else "once"});
                        final_decision = .{
                            .result = .allow,
                            .reason = approval_reason.?,
                            .risk_score = command_decision.decision.risk_score,
                            .ci_may_proceed = true,
                        };
                        try self.auditCommandEvent(session, .user_approval, display, final_decision);
                    },
                    .deny => {
                        approval_reason = try self.allocator.dupe(u8, "user denied command approval");
                        final_decision = .{
                            .result = .deny,
                            .reason = approval_reason.?,
                            .risk_score = command_decision.decision.risk_score,
                            .ci_may_proceed = false,
                        };
                        try self.auditCommandEvent(session, .user_denial, display, final_decision);
                    },
                }
            }

            if (final_decision.result == .allow or final_decision.result == .observe) {
                try self.auditCommandEvent(session, .command_allowed, display, final_decision);
                return;
            }
            try self.auditCommandEvent(session, .command_denied, display, final_decision);
            return error.CommandDenied;
        }

        fn installShims(self: *@This(), session: core.session.Session) !void {
            const self_exe = try std.fs.selfExePathAlloc(self.allocator);
            defer self.allocator.free(self_exe);
            const shim_dir = try intercept.commands.createShimDirectory(self.allocator, session.workspace_root, session.id.slice(), self_exe);
            defer self.allocator.free(shim_dir);
            try intercept.commands.prependShimPath(self.allocator, self.env_map, shim_dir);
            try self.env_map.put("AEGIS_SESSION_ID", session.id.slice());
            try self.env_map.put("AEGIS_WORKSPACE_ROOT", session.workspace_root);
            if (self.selected_policy.source_path) |path| try self.env_map.put("AEGIS_POLICY_PATH", path);
            try self.env_map.put("AEGIS_MODE", self.effective_mode.toString());
        }

        fn auditBackendCapability(self: *@This(), session: core.session.Session) !void {
            if (self.audit_context.writer == null) return;
            const target = try std.fmt.allocPrint(self.allocator, "{s} backend", .{self.backend_report.backend_name});
            defer self.allocator.free(target);
            const reason = try std.fmt.allocPrint(self.allocator, "fallback={s}; strong_sandbox={s}; network_enforcement={s}", .{
                self.backend_report.fallback_level.toString(),
                self.backend_report.get(.strong_sandbox).level.toString(),
                self.backend_report.get(.network_enforce).level.toString(),
            });
            defer self.allocator.free(reason);
            const decision: core.decision.Decision = .{
                .result = .observe,
                .reason = reason,
                .ci_may_proceed = true,
            };
            const ts = core.time.Timestamp.now();
            const ev: core.event.Event = .{
                .session_id = session.id,
                .event_id = try core.event.generateEventId(ts),
                .timestamp = ts,
                .event_type = .backend_capability,
                .actor = .{ .kind = .aegis, .display = "aegis" },
                .target = .{ .kind = .unknown, .value = target },
                .decision = decision,
            };
            try core_api.appendAuditEvent(&self.audit_context.writer.?, ev);
        }

        fn auditBackendRequirementDenied(self: *@This(), session: core.session.Session, missing: sandbox.backend.FeatureReport) !void {
            if (self.audit_context.writer == null) return;
            const target = try std.fmt.allocPrint(self.allocator, "required backend feature: {s}", .{missing.feature.key()});
            defer self.allocator.free(target);
            const reason = try std.fmt.allocPrint(self.allocator, "required backend feature unavailable: {s} is {s}", .{ missing.feature.key(), missing.level.toString() });
            defer self.allocator.free(reason);
            const decision: core.decision.Decision = .{
                .result = .deny,
                .reason = reason,
                .ci_may_proceed = false,
            };
            const ts = core.time.Timestamp.now();
            const ev: core.event.Event = .{
                .session_id = session.id,
                .event_id = try core.event.generateEventId(ts),
                .timestamp = ts,
                .event_type = .backend_capability,
                .actor = .{ .kind = .aegis, .display = "aegis" },
                .target = .{ .kind = .unknown, .value = target },
                .decision = decision,
            };
            try core_api.appendAuditEvent(&self.audit_context.writer.?, ev);
        }

        fn auditNetworkStartupEvents(self: *@This(), session: core.session.Session) !void {
            const mode = self.selected_policy.network.effectiveMode();
            if (mode == .off) {
                try self.auditNetworkDecision(session, "*", .network_connect_attempt, null);
                const decision: core.decision.Decision = .{
                    .result = .deny,
                    .reason = "network mode off; enforcement=unavailable",
                    .ci_may_proceed = false,
                };
                try self.auditNetworkDecision(session, "*", .network_connect_denied, decision);
            }
            for (self.selected_policy.network.allow) |allowed| {
                const network_decision = try intercept.network.evaluate(self.allocator, self.selected_policy, self.effective_mode, allowed, .{ .enforcement_mode = .unavailable, .ci_mode = self.effective_mode == .ci });
                defer network_decision.deinit(self.allocator);
                try self.auditNetworkDecision(session, network_decision.redacted_target, .network_connect_attempt, null);
                try self.auditNetworkDecision(session, network_decision.redacted_target, if (network_decision.decision.result == .deny) .network_connect_denied else .network_connect_allowed, network_decision.decision);
                if (network_decision.exfil_findings.len > 0) {
                    try self.auditNetworkDecision(session, network_decision.redacted_target, .network_exfiltration_suspected, network_decision.decision);
                }
            }
            for (self.selected_policy.network.deny) |denied| {
                const network_decision = try intercept.network.evaluate(self.allocator, self.selected_policy, self.effective_mode, denied, .{ .enforcement_mode = .unavailable, .ci_mode = self.effective_mode == .ci });
                defer network_decision.deinit(self.allocator);
                try self.auditNetworkDecision(session, network_decision.redacted_target, .network_connect_attempt, null);
                try self.auditNetworkDecision(session, network_decision.redacted_target, .network_connect_denied, network_decision.decision);
                if (network_decision.exfil_findings.len > 0) {
                    try self.auditNetworkDecision(session, network_decision.redacted_target, .network_exfiltration_suspected, network_decision.decision);
                }
            }
        }

        fn resolveApproval(self: *@This(), command_decision: intercept.commands.CommandDecision, display: []const u8) !intercept.approvals.ApprovalChoice {
            if (self.effective_mode == .ci) return .deny;
            const stdin_file = std.fs.File.stdin();
            if (!stdin_file.isTty()) {
                try self.stderr.writeAll("orca run: command requires approval, but stdin is non-interactive; denying.\n");
                return .deny;
            }
            var stdin_buf: [1024]u8 = undefined;
            var stdin_reader = stdin_file.readerStreaming(&stdin_buf);
            return intercept.approvals.prompt(&stdin_reader.interface, self.stderr, .{
                .command = display,
                .risk_class = command_decision.classification.risk_class.toString(),
                .risk_reason = command_decision.classification.reason,
                .policy_reason = command_decision.decision.reason,
                .matched_rule = command_decision.decision.rule_id,
            });
        }

        fn auditCommandEvent(self: *@This(), session: core.session.Session, event_type: core.event.EventType, display: []const u8, maybe_decision: ?core.decision.Decision) !void {
            if (self.audit_context.writer == null) return;
            const ts = core.time.Timestamp.now();
            const ev: core.event.Event = .{
                .session_id = session.id,
                .event_id = try core.event.generateEventId(ts),
                .timestamp = ts,
                .event_type = event_type,
                .actor = .{ .kind = .aegis, .display = "aegis" },
                .target = .{ .kind = .command, .value = display },
                .decision = maybe_decision,
            };
            try core_api.appendAuditEvent(&self.audit_context.writer.?, ev);
        }

        fn auditNetworkDecision(self: *@This(), session: core.session.Session, target: []const u8, event_type: core.event.EventType, maybe_decision: ?core.decision.Decision) !void {
            if (self.audit_context.writer == null) return;
            const ts = core.time.Timestamp.now();
            const ev: core.event.Event = .{
                .session_id = session.id,
                .event_id = try core.event.generateEventId(ts),
                .timestamp = ts,
                .event_type = event_type,
                .actor = .{ .kind = .aegis, .display = "aegis" },
                .target = .{ .kind = .network_endpoint, .value = target },
                .decision = maybe_decision,
            };
            try core_api.appendAuditEvent(&self.audit_context.writer.?, ev);
        }
    };
    var command_guard_context: CommandGuardContext = .{
        .allocator = allocator,
        .selected_policy = &loaded_policy.policy,
        .effective_mode = effective_policy_mode,
        .command_argv = options.command_argv,
        .env_map = &filtered_env.env_map,
        .audit_context = &audit_context,
        .approvals = &session_approvals,
        .backend_report = backend_report,
        .required_backend_features = options.requiredBackendFeatures(),
        .stderr = stderr,
    };

    const before_spawn = if (audit_enabled) core.supervisor.StartHook{
        .context = &audit_context,
        .callback = AuditContext.init,
    } else null;
    const on_event = if (audit_enabled) core.supervisor.EventHook{
        .context = &audit_context,
        .callback = AuditContext.append,
    } else null;

    var result = core.supervisor.run(allocator, .{
        .command = options.command_argv[0],
        .args = options.command_argv[1..],
        .workspace = options.workspace,
        .mode = session_mode,
        .session_name = options.session_name,
        .policy_source = loaded_policy.path,
        .stdio = stdio,
        .env_map = &filtered_env.env_map,
        .env_redactions = filtered_env.redactions,
        .before_spawn = before_spawn,
        .before_process_launch = if (audit_enabled) core.supervisor.StartHook{
            .context = &command_guard_context,
            .callback = CommandGuardContext.beforeProcessLaunch,
        } else null,
        .on_session_start = .{
            .context = &start_printer,
            .callback = StartPrinter.print,
        },
        .on_event = on_event,
    }) catch |err| switch (err) {
        error.CommandNotFound => {
            try stderr.print("orca run: command not found: {s}\n", .{options.command_argv[0]});
            return exit_codes.general;
        },
        error.InvalidCommand => {
            try stderr.writeAll("orca run: missing command after '--'.\n");
            return exit_codes.usage;
        },
        error.FileNotFound => {
            try stderr.print("orca run: workspace not found: {s}\n", .{options.workspace orelse "."});
            return exit_codes.general;
        },
        error.CommandDenied => {
            if (audit_context.writer) |*writer| {
                if (audit_context.session) |session| {
                    var ended = session;
                    if (audit_context.workspace_root_owned) |root| ended.workspace_root = root;
                    ended.ended_at = core.time.Timestamp.now();
                    const ts = ended.ended_at.?;
                    const ev: core.event.Event = .{
                        .session_id = ended.id,
                        .event_id = try core.event.generateEventId(ts),
                        .timestamp = ts,
                        .event_type = .session_exit,
                        .actor = .{ .kind = .aegis, .display = "aegis" },
                        .target = .{ .kind = .session, .value = ended.id.slice() },
                    };
                    try core_api.appendAuditEvent(writer, ev);
                    const final_hash = writer.finalHash() orelse "";
                    try core_api.writeAuditSummary(allocator, writer.session_dir_path, .{
                        .session = ended,
                        .status = .{ .exited = exit_codes.denial },
                        .event_count = writer.event_count,
                        .final_event_hash = final_hash,
                        .policy = loaded_policy.path,
                    });
                    try writeLastPointerNoMakePath(allocator, ended.workspace_root, ended.id.slice());
                }
            }
            try stderr.writeAll("orca run: command denied by command guard.\n");
            return exit_codes.denial;
        },
        error.BackendRequirementUnavailable => {
            if (audit_context.writer) |*writer| {
                if (audit_context.session) |session| {
                    var ended = session;
                    if (audit_context.workspace_root_owned) |root| ended.workspace_root = root;
                    ended.ended_at = core.time.Timestamp.now();
                    const ts = ended.ended_at.?;
                    const ev: core.event.Event = .{
                        .session_id = ended.id,
                        .event_id = try core.event.generateEventId(ts),
                        .timestamp = ts,
                        .event_type = .session_exit,
                        .actor = .{ .kind = .aegis, .display = "aegis" },
                        .target = .{ .kind = .session, .value = ended.id.slice() },
                    };
                    try core_api.appendAuditEvent(writer, ev);
                    const final_hash = writer.finalHash() orelse "";
                    try core_api.writeAuditSummary(allocator, writer.session_dir_path, .{
                        .session = ended,
                        .status = .{ .exited = exit_codes.unsupported },
                        .event_count = writer.event_count,
                        .final_event_hash = final_hash,
                        .policy = loaded_policy.path,
                    });
                    try writeLastPointerNoMakePath(allocator, ended.workspace_root, ended.id.slice());
                }
            }
            try stderr.writeAll("orca run: required backend feature is unavailable.\n");
            return exit_codes.unsupported;
        },
        else => {
            try stderr.print("orca run: failed to launch child: {s}\n", .{@errorName(err)});
            return exit_codes.general;
        },
    };
    defer result.deinit();

    if (audit_context.writer) |*writer| {
        const final_hash = writer.finalHash() orelse "";
        try core_api.writeAuditSummary(allocator, writer.session_dir_path, .{
            .session = result.session,
            .status = result.status,
            .event_count = writer.event_count,
            .final_event_hash = final_hash,
            .policy = loaded_policy.path,
        });
        try writer.writeLastPointer();
    }

    try printSessionEnd(stdout, result);

    return switch (result.status) {
        .exited => |code| code,
        .signal => |signal| {
            try stderr.print("orca run: child terminated by signal {d}.\n", .{signal});
            return exit_codes.child_failure;
        },
        .stopped => |signal| {
            try stderr.print("orca run: child stopped by signal {d}.\n", .{signal});
            return exit_codes.child_failure;
        },
        .unknown => |status| {
            try stderr.print("orca run: child ended with unknown status {d}.\n", .{status});
            return exit_codes.child_failure;
        },
    };
}

fn parseOptions(argv: []const []const u8, stdout: anytype, stderr: anytype) !RunOptions {
    var options: RunOptions = .{};
    var index: usize = 0;

    while (index < argv.len) : (index += 1) {
        const arg = argv[index];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            _ = try help.writeCommand(stdout, "run");
            return error.HelpShown;
        } else if (std.mem.eql(u8, arg, "--")) {
            options.command_argv = argv[index + 1 ..];
            break;
        } else if (std.mem.eql(u8, arg, "--workspace")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("orca run: --workspace requires a path.\n");
                return error.Usage;
            }
            options.workspace = argv[index];
        } else if (std.mem.eql(u8, arg, "--mode")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("orca run: --mode requires observe, ask, strict, or ci.\n");
                return error.Usage;
            }
            options.mode = parseMode(argv[index]) orelse {
                try stderr.print("orca run: unsupported mode '{s}'. Expected observe, ask, strict, or ci.\n", .{argv[index]});
                return error.Usage;
            };
            options.mode_explicit = true;
        } else if (std.mem.eql(u8, arg, "--policy")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("orca run: --policy requires a path.\n");
                return error.Usage;
            }
            options.policy_path = argv[index];
        } else if (std.mem.eql(u8, arg, "--session-name")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("orca run: --session-name requires a name.\n");
                return error.Usage;
            }
            options.session_name = argv[index];
        } else if (std.mem.eql(u8, arg, "--no-secrets")) {
            options.no_secrets = true;
        } else if (std.mem.eql(u8, arg, "--inherit-env")) {
            options.inherit_env = true;
        } else if (std.mem.eql(u8, arg, "--no-network")) {
            options.no_network = true;
            options.network_mode = .off;
        } else if (std.mem.eql(u8, arg, "--allow-network")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("orca run: --allow-network requires a domain or IP destination.\n");
                return error.Usage;
            }
            if (options.allow_network_count >= options.allow_network_values.len) {
                try stderr.writeAll("orca run: too many --allow-network rules.\n");
                return error.Usage;
            }
            options.allow_network_values[options.allow_network_count] = argv[index];
            options.allow_network_count += 1;
        } else if (std.mem.eql(u8, arg, "--network")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("orca run: --network requires observe, ask, allowlist, open, or off.\n");
                return error.Usage;
            }
            options.network_mode = policy.schema.NetworkMode.parse(argv[index]) orelse {
                try stderr.print("orca run: unsupported network mode '{s}'. Expected observe, ask, allowlist, open, or off.\n", .{argv[index]});
                return error.Usage;
            };
        } else if (std.mem.eql(u8, arg, "--require-backend")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("orca run: --require-backend requires a capability name.\n");
                return error.Usage;
            }
            if (options.required_backend_count >= options.required_backend_values.len) {
                try stderr.writeAll("orca run: too many --require-backend values.\n");
                return error.Usage;
            }
            options.required_backend_values[options.required_backend_count] = sandbox.backend.Feature.parse(argv[index]) orelse {
                try stderr.print("orca run: unsupported backend capability '{s}'.\n", .{argv[index]});
                return error.Usage;
            };
            options.required_backend_count += 1;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            try stderr.print("orca run: unknown option '{s}'.\n", .{arg});
            return error.Usage;
        } else {
            try stderr.writeAll("orca run: expected '--' before child command.\n");
            return error.Usage;
        }
    }

    if (options.command_argv.len == 0) {
        try stderr.writeAll("orca run: missing command after '--'.\n");
        return error.Usage;
    }

    return options;
}

fn applyNetworkOverlay(allocator: std.mem.Allocator, selected_policy: *policy.schema.Policy, options: RunOptions) !void {
    if (options.no_network) selected_policy.network.mode = .off;
    if (options.network_mode) |mode| selected_policy.network.mode = mode;
    const runtime_allow = options.allowNetwork();
    if (runtime_allow.len == 0) return;

    const old_allow = selected_policy.network.allow;
    const old_len = old_allow.len;
    var next = try allocator.alloc([]const u8, old_len + runtime_allow.len);
    errdefer allocator.free(next);
    for (old_allow, 0..) |value, index| next[index] = value;
    var copied: usize = 0;
    errdefer {
        for (next[old_len .. old_len + copied]) |value| allocator.free(value);
    }
    for (runtime_allow, 0..) |value, index| {
        if (std.mem.startsWith(u8, value, "*.")) {
            next[old_len + index] = try allocator.dupe(u8, value);
        } else {
            const destination = try intercept.network.parseDestination(value);
            next[old_len + index] = try destination.endpointDisplay(allocator);
        }
        copied += 1;
    }
    if (old_allow.len > 0) allocator.free(old_allow);
    selected_policy.network.allow = next;
    if (selected_policy.network.mode == null) selected_policy.network.mode = .allowlist;
}

fn installNetworkEnvironment(allocator: std.mem.Allocator, env_map: *std.process.EnvMap, network_policy: policy.schema.NetworkPolicy) !void {
    try env_map.put("AEGIS_NETWORK_POLICY_ENGINE", "active");
    try env_map.put("AEGIS_NETWORK_MODE", network_policy.effectiveMode().toString());
    try env_map.put("AEGIS_TRANSPARENT_NETWORK_ENFORCEMENT", "unavailable");
    try env_map.put("AEGIS_PROXY_MEDIATED_NETWORK_ENFORCEMENT", "unavailable");
    if (network_policy.allow.len > 0) {
        var list: std.ArrayList(u8) = .empty;
        defer list.deinit(allocator);
        for (network_policy.allow, 0..) |allowed, index| {
            if (index > 0) try list.append(allocator, ',');
            try list.appendSlice(allocator, allowed);
        }
        const owned = try list.toOwnedSlice(allocator);
        defer allocator.free(owned);
        try env_map.put("AEGIS_NETWORK_ALLOW", owned);
    }
}

fn installBackendEnvironment(env_map: *std.process.EnvMap, report: sandbox.backend.ReportSet) !void {
    try env_map.put("AEGIS_BACKEND", report.backend_name);
    try env_map.put("AEGIS_BACKEND_FALLBACK", report.fallback_level.toString());
    try env_map.put("AEGIS_BACKEND_ENV_FILTERING", report.get(.env_filtering).level.toString());
    try env_map.put("AEGIS_BACKEND_PATH_STAGING", report.get(.path_staging).level.toString());
    try env_map.put("AEGIS_BACKEND_SHELL_WRAPPING", report.get(.shell_wrapping).level.toString());
    try env_map.put("AEGIS_BACKEND_PATH_SHIMS", report.get(.path_shims).level.toString());
    try env_map.put("AEGIS_BACKEND_STRONG_SANDBOX", report.get(.strong_sandbox).level.toString());
    try env_map.put("AEGIS_BACKEND_PROCESS_SUPERVISION", report.get(.process_supervision).level.toString());
    try env_map.put("AEGIS_BACKEND_USER_NAMESPACES", report.get(.user_namespaces).level.toString());
    try env_map.put("AEGIS_BACKEND_MOUNT_NAMESPACES", report.get(.mount_namespaces).level.toString());
    try env_map.put("AEGIS_BACKEND_SECCOMP", report.get(.seccomp).level.toString());
    try env_map.put("AEGIS_BACKEND_LANDLOCK", report.get(.landlock).level.toString());
    try env_map.put("AEGIS_BACKEND_CGROUPS", report.get(.cgroups).level.toString());
    try env_map.put("AEGIS_BACKEND_NETWORK_OBSERVE", report.get(.network_observe).level.toString());
    try env_map.put("AEGIS_BACKEND_NETWORK_ENFORCEMENT", report.get(.network_enforce).level.toString());
}

fn parseMode(value: []const u8) ?core.types.Mode {
    if (std.mem.eql(u8, value, "observe")) return .observe;
    if (std.mem.eql(u8, value, "ask")) return .ask;
    if (std.mem.eql(u8, value, "strict")) return .strict;
    if (std.mem.eql(u8, value, "ci")) return .ci;
    return null;
}

fn coreModeToPolicyMode(mode: core.types.Mode) policy.schema.Mode {
    return switch (mode) {
        .observe => .observe,
        .ask => .ask,
        .strict => .strict,
        .ci => .ci,
    };
}

fn printSessionStart(stdout: anytype, session: core.session.Session) !void {
    try stdout.print(
        \\Orca session started: {s}
        \\Workspace: {s}
        \\Mode: {s}
        \\
    , .{
        session.id.slice(),
        session.workspace_root,
        session.mode.toString(),
    });
    if (session.session_name) |name| {
        try stdout.print("Session: {s}\n", .{name});
    }
    try stdout.writeAll("\n");
}

fn printSessionEnd(stdout: anytype, result: core.supervisor.SessionResult) !void {
    try stdout.print("\nOrca session ended: exit code {d}\n", .{result.exitCode()});
}

fn flushIfSupported(writer: anytype) !void {
    const Writer = @TypeOf(writer);
    switch (@typeInfo(Writer)) {
        .pointer => |pointer| {
            if (@hasDecl(pointer.child, "flush")) {
                try writer.flush();
            }
        },
        else => {
            if (@hasDecl(Writer, "flush")) {
                try writer.flush();
            }
        },
    }
}

test "run rejects missing child command" {
    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(&.{"--"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "missing command") != null);
}

test "run rejects child command without separator" {
    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(&.{"echo"}, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.usage, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "expected '--'") != null);
}

test "run reports missing command usefully" {
    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try commandForTest(&.{ "--", "aegis-definitely-missing-command" }, stdout_stream.writer(), stderr_stream.writer(), .ignore);
    try std.testing.expectEqual(exit_codes.general, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "command not found") != null);
}

pub fn commandForTest(argv: []const []const u8, stdout: anytype, stderr: anytype, stdio: core.supervisor.StdioBehavior) !u8 {
    return commandWithStdio(argv, stdout, stderr, stdio, false);
}

test "run accepts policy path and uses policy mode when mode is not explicit" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    {
        const file = try tmp.dir.createFile("strict.yaml", .{});
        defer file.close();
        try file.writeAll(policy.presets.text(.strict));
    }
    const path = try tmp.dir.realpathAlloc(std.testing.allocator, "strict.yaml");
    defer std.testing.allocator.free(path);

    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try commandForTest(&.{ "--policy", path, "--", "zig", "version" }, stdout_stream.writer(), stderr_stream.writer(), .ignore);
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expect(std.mem.indexOf(u8, stdout_stream.getWritten(), "Mode: strict") != null);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());
}

test "run rejects inherit-env when selected policy disallows it" {
    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try commandForTest(&.{ "--policy", "policies/strict.yaml", "--inherit-env", "--", "zig", "version" }, stdout_stream.writer(), stderr_stream.writer(), .ignore);
    try std.testing.expectEqual(exit_codes.general, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "--inherit-env is not allowed") != null);
}

test "run command guard denies ci ask without prompting and audits command events" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [2048]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(&.{ "--workspace", root, "--mode", "ci", "--", "npm", "install", "OPENAI_API_KEY=sk-fakeSyntheticOpenAIKey1234567890" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.denial, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "command denied") != null);

    const events = try readLastEvents(std.testing.allocator, root);
    defer std.testing.allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"type\":\"command_attempt\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"type\":\"command_denied\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "sk-fakeSyntheticOpenAIKey") == null);
    try std.testing.expect(std.mem.indexOf(u8, events, "[REDACTED:env:OPENAI_API_KEY:sha256:") != null);
}

test "run command guard allows safe command and creates session shim directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [2048]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(&.{ "--workspace", root, "--", "true" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    const session_id = try readLastSessionId(std.testing.allocator, root);
    defer std.testing.allocator.free(session_id);
    const shim_path = try std.fs.path.join(std.testing.allocator, &.{ root, ".aegis", "sessions", session_id, "shims", "git" });
    defer std.testing.allocator.free(shim_path);
    try std.fs.cwd().access(shim_path, .{});

    const events = try readLastEvents(std.testing.allocator, root);
    defer std.testing.allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"type\":\"command_allowed\"") != null);
}

test "run command guard denies destructive command before spawn" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [2048]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(&.{ "--workspace", root, "--", "rm", "-rf", "/" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.denial, code);
    const events = try readLastEvents(std.testing.allocator, root);
    defer std.testing.allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"type\":\"command_denied\"") != null);
}

test "run no-network sets network mode off and audits denied network state" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [2048]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(&.{ "--workspace", root, "--no-network", "--", "true" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);
    const events = try readLastEvents(std.testing.allocator, root);
    defer std.testing.allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"type\":\"network_connect_denied\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"type\":\"network_exfiltration_suspected\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "network mode off") != null);
}

test "run allow-network adds temporary allow rule and redacts URL secrets in audit" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [2048]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(&.{ "--workspace", root, "--allow-network", "https://api.github.com/repos?token=sk-fakeSyntheticOpenAIKey1234567890", "--", "true" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.success, code);
    const events = try readLastEvents(std.testing.allocator, root);
    defer std.testing.allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"type\":\"network_connect_allowed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "api.github.com") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "sk-fakeSyntheticOpenAIKey") == null);
}

test "run exports backend capability status to child environment" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [2048]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try commandForTest(&.{ "--workspace", root, "--", "/bin/sh", "-c", "env > backend-env.txt" }, stdout_stream.writer(), stderr_stream.writer(), .ignore);
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expectEqualStrings("", stderr_stream.getWritten());

    const written = try tmp.dir.readFileAlloc(std.testing.allocator, "backend-env.txt", 8192);
    defer std.testing.allocator.free(written);
    try std.testing.expect(std.mem.indexOf(u8, written, "AEGIS_BACKEND=") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "AEGIS_BACKEND_ENV_FILTERING=") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "AEGIS_BACKEND_PATH_STAGING=") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "AEGIS_BACKEND_SHELL_WRAPPING=") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "AEGIS_BACKEND_PATH_SHIMS=") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "AEGIS_BACKEND_STRONG_SANDBOX=") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "AEGIS_BACKEND_PROCESS_SUPERVISION=") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "AEGIS_BACKEND_NETWORK_OBSERVE=") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "AEGIS_BACKEND_NETWORK_ENFORCEMENT=") != null);
}

test "run require-backend fails closed when requested feature is unavailable" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [2048]u8 = undefined;
    var stdout_stream = std.io.fixedBufferStream(&stdout_buf);
    var stderr_stream = std.io.fixedBufferStream(&stderr_buf);

    const code = try command(&.{ "--workspace", root, "--mode", "ci", "--require-backend", "network_enforce", "--", "true" }, stdout_stream.writer(), stderr_stream.writer());
    try std.testing.expectEqual(exit_codes.unsupported, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_stream.getWritten(), "required backend feature is unavailable") != null);

    const events = try readLastEvents(std.testing.allocator, root);
    defer std.testing.allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"type\":\"backend_capability\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "required backend feature unavailable") != null);
}

fn readLastSessionId(allocator: std.mem.Allocator, root: []const u8) ![]u8 {
    const last_path = try std.fs.path.join(allocator, &.{ root, ".aegis", "last" });
    defer allocator.free(last_path);
    const text = try std.fs.cwd().readFileAlloc(allocator, last_path, core.limits.max_session_id_len + 2);
    defer allocator.free(text);
    return try allocator.dupe(u8, std.mem.trim(u8, text, " \t\r\n"));
}

fn readLastEvents(allocator: std.mem.Allocator, root: []const u8) ![]u8 {
    const session_id = try readLastSessionId(allocator, root);
    defer allocator.free(session_id);
    const events_path = try std.fs.path.join(allocator, &.{ root, ".aegis", "sessions", session_id, "events.jsonl" });
    defer allocator.free(events_path);
    return try std.fs.cwd().readFileAlloc(allocator, events_path, 64 * 1024);
}

fn writeLastPointerNoMakePath(allocator: std.mem.Allocator, workspace_root: []const u8, session_id: []const u8) !void {
    const last_path = try std.fs.path.join(allocator, &.{ workspace_root, ".aegis", "last" });
    defer allocator.free(last_path);
    const file = try std.fs.cwd().createFile(last_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(session_id);
    try file.writeAll("\n");
    try file.sync();
}
