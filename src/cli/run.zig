const std = @import("std");
const builtin = @import("builtin");

const core = @import("orca_core").core;
const supervisor = core.supervisor;
const core_api = @import("orca_core").api;
const intercept = @import("../intercept/mod.zig");
const policy = @import("orca_core").policy;
const sandbox = @import("../sandbox/mod.zig");
const exit_codes = @import("exit_codes.zig");
const help = @import("help.zig");
const style = @import("style.zig");
const shell_eval = @import("shell_eval.zig");
const rust_visibility = @import("rust_visibility.zig");
const tui = @import("../tui/mod.zig");
const build_options = @import("build_options");
const suggestions = @import("suggestions.zig");

const RunOptions = struct {
    workspace: ?[]const u8 = null,
    mode: core.types.Mode = .observe,
    mode_explicit: bool = false,
    policy_path: ?[]const u8 = null,
    session_name: ?[]const u8 = null,
    no_secrets: bool = false,
    secretless: bool = false,
    inherit_env: bool = false,
    no_network: bool = false,
    network_mode: ?policy.schema.NetworkMode = null,
    network_backend: ?policy.schema.NetworkBackend = null,
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

pub fn command(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    return commandWithStdio(io, argv, stdout, stderr, .inherit, true);
}

fn commandWithStdio(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype, stdio: supervisor.StdioBehavior, audit_enabled: bool) !u8 {
    return commandWithStdioAndEnv(io, argv, stdout, stderr, stdio, audit_enabled, null, null);
}

fn commandWithStdioAndEnv(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype, stdio: supervisor.StdioBehavior, audit_enabled: bool, current_env_override: ?*const std.process.Environ.Map, shell_evaluator: ?shell_eval.ShellCommandEvaluatorFn) !u8 {
    const options = parseOptions(io, argv, stdout, stderr) catch |err| switch (err) {
        error.HelpShown => return exit_codes.success,
        error.Usage => return exit_codes.usage,
        else => return err,
    };

    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const workspace_root_for_policy = supervisor.resolveWorkspaceRoot(io, allocator, options.workspace, ".") catch |err| switch (err) {
        error.FileNotFound => {
            try stderr.print("orca run: workspace not found: {s}\n", .{options.workspace orelse "."});
            return exit_codes.general;
        },
        else => return err,
    };
    defer allocator.free(workspace_root_for_policy);

    var loaded_policy = core_api.discoverPolicy(io, allocator, options.policy_path, workspace_root_for_policy) catch |err| {
        try stderr.print("orca run: invalid policy: {s}\n", .{@errorName(err)});
        return exit_codes.general;
    };
    defer loaded_policy.deinit();
    const effective_policy_mode = if (options.mode_explicit) coreModeToPolicyMode(options.mode) else loaded_policy.policy.mode();
    const session_mode = effective_policy_mode.toCoreMode();

    // Detect first session *before* any .orca/sessions/ creation so the warm welcome
    // celebration can be emitted exactly once for a brand-new user/workspace.
    const is_first_session = isFirstSession(io, allocator, workspace_root_for_policy);

    try applyNetworkOverlay(allocator, loaded_policy.innerMutPtr(), options);

    const env_request: intercept.env.Request = .{
        .no_secrets = options.no_secrets,
        .secretless = options.secretless,
        .inherit_env = options.inherit_env,
    };
    var filtered_env = (if (current_env_override) |current_env|
        intercept.env.filterMap(allocator, current_env, loaded_policy.innerPtr(), effective_policy_mode, env_request)
    else
        intercept.env.filterCurrent(allocator, loaded_policy.innerPtr(), effective_policy_mode, env_request)) catch |err| switch (err) {
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
    try installNetworkEnvironment(allocator, &filtered_env.env_map, loaded_policy.innerPtr().network);
    var proxy_runtime: ?intercept.proxy.Runtime = null;
    defer if (proxy_runtime) |*runtime| runtime.deinit();
    const proxy_required_by_backend = loaded_policy.innerPtr().network.effectiveBackend() == .proxy;
    if (proxy_required_by_backend) {
        proxy_runtime = intercept.proxy.start(allocator, loaded_policy.innerPtr(), effective_policy_mode) catch |err| blk: {
            if (effective_policy_mode == .strict or effective_policy_mode == .ci or requiresBackend(options, .network_enforce)) {
                try stderr.print("orca run: proxy network backend unavailable: {s}\n", .{@errorName(err)});
                return exit_codes.unsupported;
            }
            try stderr.print("orca run: proxy network backend unavailable; continuing without proxy in observe-compatible mode: {s}\n", .{@errorName(err)});
            break :blk null;
        };
        if (proxy_runtime) |runtime| {
            try intercept.network.appendProxyEnvironment(&filtered_env.env_map, runtime.bindUrl(), "localhost,127.0.0.1,::1");
            try filtered_env.env_map.put("ORCA_PROXY_MEDIATED_NETWORK_ENFORCEMENT", "active");
            try filtered_env.env_map.put("ORCA_PROXY_BIND", runtime.bindUrl());
            try filtered_env.env_map.put("ORCA_PROXY_HTTPS_VISIBILITY", "host-port-only");
            try filtered_env.env_map.put("ORCA_PROXY_METHOD_PATH_VISIBILITY", "http-and-cooperative-hooks");
        }
    }
    const backend_report = sandbox.backend.detect(core.platform.detectOs());
    try installBackendEnvironment(&filtered_env.env_map, backend_report);

    const StartPrinter = struct {
        io: std.Io,
        writer: @TypeOf(stdout),

        pub fn print(context: *anyopaque, session: core.session.Session) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            try printSessionStart(self.io, self.writer, session);
            try flushIfSupported(self.writer);
        }
    };

    const ProxyHealthContext = struct {
        runtime: *intercept.proxy.Runtime,

        pub fn healthy(context: *anyopaque) bool {
            const self: *@This() = @ptrCast(@alignCast(context));
            return self.runtime.isHealthy();
        }
    };

    var start_printer: StartPrinter = .{ .io = io, .writer = stdout };
    const AuditContext = struct {
        io: std.Io,
        allocator: std.mem.Allocator,
        writer: ?core_api.AuditWriter = null,
        session: ?core.session.Session = null,
        workspace_root_owned: ?[]const u8 = null,

        pub fn init(context: *anyopaque, session: core.session.Session) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.session = session;
            self.workspace_root_owned = try self.allocator.dupe(u8, session.workspace_root);
            self.writer = try core_api.createAuditWriter(self.io, self.allocator, session);
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
    var audit_context: AuditContext = .{ .io = io, .allocator = allocator };
    defer audit_context.deinit();

    var session_approvals = intercept.approvals.SessionApprovals.init(allocator);
    defer session_approvals.deinit();

    const CommandGuardContext = struct {
        io: std.Io,
        allocator: std.mem.Allocator,
        selected_policy: *const policy.schema.Policy,
        effective_mode: policy.schema.Mode,
        command_argv: []const []const u8,
        env_map: *std.process.Environ.Map,
        audit_context: *AuditContext,
        approvals: *intercept.approvals.SessionApprovals,
        backend_report: sandbox.backend.ReportSet,
        required_backend_features: []const sandbox.backend.Feature,
        proxy_bind: ?[]const u8,
        stderr: @TypeOf(stderr),
        shell_evaluator: ?shell_eval.ShellCommandEvaluatorFn = null,
        workspace_root: []const u8,
        // Phase 1 UX: captures the rule id of the most recently denied command so
        // the `error.CommandDenied` handler can render a rich guardian block with a
        // plain-English reason + risk meter. Allocator-owned; freed by the handler.
        // Null on the fail-closed / user-denial paths (graceful degrade).
        last_denied_rule_id: ?[]const u8 = null,

        pub fn beforeProcessLaunch(context: *anyopaque, session: core.session.Session) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            try self.installShims(session);
            try self.auditBackendCapability(session);
            if (self.backend_report.firstMissingRequired(self.required_backend_features)) |missing| {
                if (!(missing.feature == .network_enforce and self.proxy_bind != null)) {
                    try self.auditBackendRequirementDenied(session, missing);
                    return error.BackendRequirementUnavailable;
                }
            }
            if (self.proxy_bind) |bind| try self.auditNetworkDecision(session, bind, .network_proxy_start, .{ .result = .observe, .reason = "proxy-mediated network backend started", .ci_may_proceed = true });
            try self.auditNetworkStartupEvents(session);
            const display = try intercept.commands.displayArgvAlloc(self.allocator, self.command_argv);
            defer self.allocator.free(display);

            try self.auditCommandEvent(session, .command_attempt, rust_visibility.target_summary_shell, null, .{});

            var rust_metadata: core.event.EventMetadata = .{};
            defer rust_metadata.deinit(self.allocator);

            const audit_options = shell_eval.ShellAuditOptions{
                .io = self.audit_context.io,
                .workspace_root = self.workspace_root,
                .event_source = rust_visibility.event_source_run,
                .session_id = session.id.slice(),
                .verified = false,
            };

            var command_decision = try shell_eval.evaluateCommand(
                self.allocator,
                self.effective_mode,
                self.command_argv,
                self.workspace_root,
                self.shell_evaluator,
                &rust_metadata,
                audit_options,
            );
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
                try self.auditCommandEvent(session, .command_approval_requested, rust_visibility.target_summary_shell, final_decision, rust_metadata);
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
                        try self.auditCommandEvent(session, .user_approval, rust_visibility.target_summary_shell, final_decision, rust_metadata);
                    },
                    .deny => {
                        approval_reason = try self.allocator.dupe(u8, "user denied command approval");
                        final_decision = .{
                            .result = .deny,
                            .reason = approval_reason.?,
                            .risk_score = command_decision.decision.risk_score,
                            .ci_may_proceed = false,
                        };
                        try self.auditCommandEvent(session, .user_denial, rust_visibility.target_summary_shell, final_decision, rust_metadata);
                    },
                }
            }

            if (final_decision.result == .allow or final_decision.result == .observe) {
                try self.auditCommandEvent(session, .command_allowed, rust_visibility.target_summary_shell, final_decision, rust_metadata);
                return;
            }
            try self.auditCommandEvent(session, .command_denied, rust_visibility.target_summary_shell, final_decision, rust_metadata);
            // Capture the matched rule id for the rich deny block. The decision is
            // freed by `defer command_decision.deinit` below; dupe so the handler
            // can read it after this closure returns. `owned_rule_id` carries the
            // daemon's pattern_name (e.g. "rm-rf-root-home"); null on fail-closed.
            if (command_decision.owned_rule_id) |rid| {
                self.last_denied_rule_id = try self.allocator.dupe(u8, rid);
            }
            return error.CommandDenied;
        }

        fn installShims(self: *@This(), session: core.session.Session) !void {
            const self_exe = try std.process.executablePathAlloc(self.audit_context.io, self.allocator);
            defer self.allocator.free(self_exe);
            const shim_dir = try intercept.commands.createShimDirectory(self.audit_context.io, self.allocator, session.workspace_root, session.id.slice(), self_exe);
            defer self.allocator.free(shim_dir);
            try intercept.commands.prependShimPath(self.allocator, self.env_map, shim_dir);
            try self.env_map.put("ORCA_SESSION_ID", session.id.slice());
            try self.env_map.put("ORCA_WORKSPACE_ROOT", session.workspace_root);
            if (self.selected_policy.source_path) |path| try self.env_map.put("ORCA_POLICY_PATH", path);
            try self.env_map.put("ORCA_MODE", self.effective_mode.toString());
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
            const ts = core.time.Timestamp.now(self.audit_context.io);
            const ev: core.event.Event = .{
                .session_id = session.id,
                .event_id = try core.event.generateEventId(ts),
                .timestamp = ts,
                .event_type = .backend_capability,
                .actor = .{ .kind = .orca, .display = "orca" },
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
            const ts = core.time.Timestamp.now(self.audit_context.io);
            const ev: core.event.Event = .{
                .session_id = session.id,
                .event_id = try core.event.generateEventId(ts),
                .timestamp = ts,
                .event_type = .backend_capability,
                .actor = .{ .kind = .orca, .display = "orca" },
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
            const stdin_file = std.Io.File.stdin();
            if (!(try stdin_file.isTty(self.io))) {
                try self.stderr.writeAll("orca run: command requires approval, but stdin is non-interactive; denying.\n");
                return .deny;
            }
            var stdin_buf: [1024]u8 = undefined;
            var stdin_reader = stdin_file.readerStreaming(self.io, &stdin_buf);
            return intercept.approvals.prompt(&stdin_reader.interface, self.stderr, .{
                .command = display,
                .risk_class = command_decision.classification.risk_class.toString(),
                .risk_reason = command_decision.classification.reason,
                .policy_reason = command_decision.decision.reason,
                .matched_rule = command_decision.decision.rule_id,
            });
        }

        fn auditCommandEvent(self: *@This(), session: core.session.Session, event_type: core.event.EventType, target: []const u8, maybe_decision: ?core.decision.Decision, metadata: core.event.EventMetadata) !void {
            if (self.audit_context.writer == null) return;
            const ts = core.time.Timestamp.now(self.audit_context.io);
            const ev: core.event.Event = .{
                .session_id = session.id,
                .event_id = try core.event.generateEventId(ts),
                .timestamp = ts,
                .event_type = event_type,
                .actor = .{ .kind = .orca, .display = "orca" },
                .target = .{ .kind = .command, .value = target },
                .decision = maybe_decision,
                .metadata = metadata,
            };
            try core_api.appendAuditEvent(&self.audit_context.writer.?, ev);
        }

        fn auditNetworkDecision(self: *@This(), session: core.session.Session, target: []const u8, event_type: core.event.EventType, maybe_decision: ?core.decision.Decision) !void {
            if (self.audit_context.writer == null) return;
            const ts = core.time.Timestamp.now(self.audit_context.io);
            const ev: core.event.Event = .{
                .session_id = session.id,
                .event_id = try core.event.generateEventId(ts),
                .timestamp = ts,
                .event_type = event_type,
                .actor = .{ .kind = .orca, .display = "orca" },
                .target = .{ .kind = .network_endpoint, .value = target },
                .decision = maybe_decision,
            };
            try core_api.appendAuditEvent(&self.audit_context.writer.?, ev);
        }
    };
    var command_guard_context: CommandGuardContext = .{
        .io = io,
        .allocator = allocator,
        .selected_policy = loaded_policy.innerPtr(),
        .effective_mode = effective_policy_mode,
        .command_argv = options.command_argv,
        .env_map = &filtered_env.env_map,
        .audit_context = &audit_context,
        .approvals = &session_approvals,
        .backend_report = backend_report,
        .required_backend_features = options.requiredBackendFeatures(),
        .proxy_bind = if (proxy_runtime) |runtime| runtime.bindUrl() else null,
        .stderr = stderr,
        .workspace_root = workspace_root_for_policy,
        .shell_evaluator = shell_evaluator,
    };
    const proxy_fail_closed = proxy_runtime != null and proxy_required_by_backend and (effective_policy_mode == .strict or effective_policy_mode == .ci or requiresBackend(options, .network_enforce));
    var proxy_health_context: ProxyHealthContext = undefined;
    const health_monitor: ?supervisor.HealthMonitor = if (proxy_fail_closed) blk: {
        proxy_health_context = .{ .runtime = &proxy_runtime.? };
        break :blk .{
            .context = &proxy_health_context,
            .callback = ProxyHealthContext.healthy,
        };
    } else null;

    const before_spawn = if (audit_enabled) supervisor.StartHook{
        .context = &audit_context,
        .callback = AuditContext.init,
    } else null;
    const on_event = if (audit_enabled) supervisor.EventHook{
        .context = &audit_context,
        .callback = AuditContext.append,
    } else null;

    var result = supervisor.run(io, allocator, .{
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
        .before_process_launch = if (audit_enabled) supervisor.StartHook{
            .context = &command_guard_context,
            .callback = CommandGuardContext.beforeProcessLaunch,
        } else null,
        .on_session_start = .{
            .context = &start_printer,
            .callback = StartPrinter.print,
        },
        .on_event = on_event,
        .health_monitor = health_monitor,
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
                    ended.ended_at = core.time.Timestamp.now(audit_context.io);
                    const ts = ended.ended_at.?;
                    const ev: core.event.Event = .{
                        .session_id = ended.id,
                        .event_id = try core.event.generateEventId(ts),
                        .timestamp = ts,
                        .event_type = .session_exit,
                        .actor = .{ .kind = .orca, .display = "orca" },
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
                        .product_label = "Orca",
                    });
                    try writeLastPointerNoMakePath(allocator, ended.workspace_root, ended.id.slice());
                }
            }
            // Phase 1 UX: render a rich "guardian block" to human stderr instead of
            // the old flat one-liner. --json/robot/machine output is unaffected (it
            // never reaches this human stderr path). Graceful-degrades when the
            // matched rule id is unknown/null (fail-closed / user-denial paths).
            renderDenyBlock(
                io,
                stderr,
                allocator,
                options.command_argv,
                command_guard_context.last_denied_rule_id,
                loaded_policy.path,
                effective_policy_mode.toString(),
            ) catch |render_err| {
                // Never let a presentation failure mask the deny or alter the exit
                // code; fall back to a minimal message and continue to denial.
                stderr.print("orca run: command denied by command guard ({s}).\n", .{@errorName(render_err)}) catch {};
            };
            if (command_guard_context.last_denied_rule_id) |rid| allocator.free(rid);
            command_guard_context.last_denied_rule_id = null;
            return exit_codes.denial;
        },
        error.BackendRequirementUnavailable => {
            if (audit_context.writer) |*writer| {
                if (audit_context.session) |session| {
                    var ended = session;
                    if (audit_context.workspace_root_owned) |root| ended.workspace_root = root;
                    ended.ended_at = core.time.Timestamp.now(audit_context.io);
                    const ts = ended.ended_at.?;
                    const ev: core.event.Event = .{
                        .session_id = ended.id,
                        .event_id = try core.event.generateEventId(ts),
                        .timestamp = ts,
                        .event_type = .session_exit,
                        .actor = .{ .kind = .orca, .display = "orca" },
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
                        .product_label = "Orca",
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

    const required_proxy_failed = proxy_fail_closed and if (proxy_runtime) |runtime| runtime.failed() else false;
    const final_status: core.process.ChildStatus = if (required_proxy_failed) .{ .exited = exit_codes.unsupported } else result.status;

    if (audit_context.writer) |*writer| {
        if (audit_context.session) |session| {
            if (proxy_runtime) |runtime| {
                runtime.waitForIdle(1 * std.time.ns_per_s) catch {};
                const proxy_events = try runtime.snapshotAuditEvents(allocator);
                defer runtime.freeAuditEvents(allocator, proxy_events);
                for (proxy_events) |proxy_event| {
                    const event_ts = core.time.Timestamp.now(audit_context.io);
                    const ev: core.event.Event = .{
                        .session_id = session.id,
                        .event_id = try core.event.generateEventId(event_ts),
                        .timestamp = event_ts,
                        .event_type = proxy_event.event_type,
                        .actor = .{ .kind = .orca, .display = "orca" },
                        .target = .{ .kind = .network_endpoint, .value = proxy_event.target },
                        .decision = if (proxy_event.result) |decision_result| .{
                            .result = decision_result,
                            .reason = proxy_event.reason orelse "proxy-mediated network decision",
                            .ci_may_proceed = proxy_event.ci_may_proceed,
                        } else null,
                    };
                    try core_api.appendAuditEvent(writer, ev);
                }
                const ts = core.time.Timestamp.now(audit_context.io);
                const ev: core.event.Event = .{
                    .session_id = session.id,
                    .event_id = try core.event.generateEventId(ts),
                    .timestamp = ts,
                    .event_type = .network_proxy_stop,
                    .actor = .{ .kind = .orca, .display = "orca" },
                    .target = .{ .kind = .network_endpoint, .value = runtime.bindUrl() },
                    .decision = .{ .result = if (required_proxy_failed) .deny else .observe, .reason = if (required_proxy_failed) "required proxy backend failed during child run" else "proxy-mediated network backend stopped", .ci_may_proceed = !required_proxy_failed },
                };
                try core_api.appendAuditEvent(writer, ev);
            }
        }
        const final_hash = writer.finalHash() orelse "";
        try core_api.writeAuditSummary(allocator, writer.session_dir_path, .{
            .session = result.session,
            .status = final_status,
            .event_count = writer.event_count,
            .final_event_hash = final_hash,
            .policy = loaded_policy.path,
            .product_label = "Orca",
        });
        try writer.writeLastPointer();
    }

    try printSessionEnd(io, stdout, result, is_first_session);

    if (required_proxy_failed) {
        try stderr.writeAll("orca run: required proxy backend failed during child run; child was terminated.\n");
        return exit_codes.unsupported;
    }

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

fn parseOptions(io: std.Io, argv: []const []const u8, stdout: anytype, stderr: anytype) !RunOptions {
    var options: RunOptions = .{};
    var index: usize = 0;

    while (index < argv.len) : (index += 1) {
        const arg = argv[index];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            _ = try help.writeCommand(io, stdout, "run");
            return error.HelpShown;
        } else if (std.mem.eql(u8, arg, "--")) {
            options.command_argv = argv[index + 1 ..];
            break;
        } else if (std.mem.eql(u8, arg, "--ci")) {
            options.mode = .ci;
            options.mode_explicit = true;
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
        } else if (std.mem.eql(u8, arg, "--secretless")) {
            options.secretless = true;
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
        } else if (std.mem.eql(u8, arg, "--network-backend")) {
            index += 1;
            if (index >= argv.len) {
                try stderr.writeAll("orca run: --network-backend requires decision-only or proxy.\n");
                return error.Usage;
            }
            options.network_backend = policy.schema.NetworkBackend.parse(argv[index]) orelse {
                try stderr.print("orca run: unsupported network backend '{s}'. Expected decision-only or proxy.\n", .{argv[index]});
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
            try suggestions.writeUnknownOption(stderr, "orca run", arg, &.{ "--workspace", "--mode", "--policy", "--session-name", "--no-secrets", "--secretless", "--inherit-env", "--no-network", "--allow-network", "--network", "--network-backend", "--require-backend", "--help", "-h" }, "run");
            return error.Usage;
        } else {
            try stderr.writeAll("orca run: expected '--' before the command you want to run.\n" ++
                "\n" ++
                "Example:\n" ++
                "  orca run -- codex\n" ++
                "  orca run --mode strict -- npm install\n" ++
                "\n" ++
                "Run 'orca help run' for more examples.\n");
            return error.Usage;
        }
    }

    if (options.command_argv.len == 0) {
        try stderr.writeAll("orca run: missing command after '--'.\n" ++
            "\n" ++
            "Example:\n" ++
            "  orca run -- echo 'hello world'\n");
        return error.Usage;
    }

    return options;
}

fn applyNetworkOverlay(allocator: std.mem.Allocator, selected_policy: *policy.schema.Policy, options: RunOptions) !void {
    if (options.no_network) selected_policy.network.mode = .off;
    if (options.network_mode) |mode| selected_policy.network.mode = mode;
    if (options.network_backend) |backend| selected_policy.network.backend = backend;
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

fn requiresBackend(options: RunOptions, feature: sandbox.backend.Feature) bool {
    for (options.requiredBackendFeatures()) |required| {
        if (required == feature) return true;
    }
    return false;
}

fn installNetworkEnvironment(allocator: std.mem.Allocator, env_map: *std.process.Environ.Map, network_policy: policy.schema.NetworkPolicy) !void {
    try env_map.put("ORCA_NETWORK_POLICY_ENGINE", "active");
    try env_map.put("ORCA_NETWORK_MODE", network_policy.effectiveMode().toString());
    try env_map.put("ORCA_TRANSPARENT_NETWORK_ENFORCEMENT", "unavailable");
    try env_map.put("ORCA_PROXY_MEDIATED_NETWORK_ENFORCEMENT", "unavailable");
    if (network_policy.allow.len > 0) {
        var list: std.ArrayList(u8) = .empty;
        defer list.deinit(allocator);
        for (network_policy.allow, 0..) |allowed, index| {
            if (index > 0) try list.append(allocator, ',');
            try list.appendSlice(allocator, allowed);
        }
        const owned = try list.toOwnedSlice(allocator);
        defer allocator.free(owned);
        try env_map.put("ORCA_NETWORK_ALLOW", owned);
    }
}

fn installBackendEnvironment(env_map: *std.process.Environ.Map, report: sandbox.backend.ReportSet) !void {
    try env_map.put("ORCA_BACKEND", report.backend_name);
    try env_map.put("ORCA_BACKEND_FALLBACK", report.fallback_level.toString());
    try env_map.put("ORCA_BACKEND_ENV_FILTERING", report.get(.env_filtering).level.toString());
    try env_map.put("ORCA_BACKEND_PATH_STAGING", report.get(.path_staging).level.toString());
    try env_map.put("ORCA_BACKEND_SHELL_WRAPPING", report.get(.shell_wrapping).level.toString());
    try env_map.put("ORCA_BACKEND_PATH_SHIMS", report.get(.path_shims).level.toString());
    try env_map.put("ORCA_BACKEND_STRONG_SANDBOX", report.get(.strong_sandbox).level.toString());
    try env_map.put("ORCA_BACKEND_PROCESS_SUPERVISION", report.get(.process_supervision).level.toString());
    try env_map.put("ORCA_BACKEND_USER_NAMESPACES", report.get(.user_namespaces).level.toString());
    try env_map.put("ORCA_BACKEND_MOUNT_NAMESPACES", report.get(.mount_namespaces).level.toString());
    try env_map.put("ORCA_BACKEND_SECCOMP", report.get(.seccomp).level.toString());
    try env_map.put("ORCA_BACKEND_LANDLOCK", report.get(.landlock).level.toString());
    try env_map.put("ORCA_BACKEND_CGROUPS", report.get(.cgroups).level.toString());
    try env_map.put("ORCA_BACKEND_NETWORK_OBSERVE", report.get(.network_observe).level.toString());
    try env_map.put("ORCA_BACKEND_NETWORK_ENFORCEMENT", report.get(.network_enforce).level.toString());
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

fn printSessionStart(io: std.Io, stdout: anytype, session: core.session.Session) !void {
    // Phase 2 brand cohesion: replace the hand-rolled `─────` + shield line with
    // the shared compact brand banner (status chip carries the "watching" intent)
    // and a key-value grid for Session / Workspace / Mode / Name. The shield +
    // first-run celebration stay in `printSessionEnd` (gold standard; Phase 7).
    try tui.render.banner(io, stdout, build_options.version, "watching this session");

    var rows: [4]tui.render.KV = .{
        .{ .label = "Session", .value = session.id.slice() },
        .{ .label = "Workspace", .value = session.workspace_root },
        .{ .label = "Mode", .value = session.mode.toString() },
        .{ .label = "Name", .value = "" },
    };
    var count: usize = 3;
    if (session.session_name) |name| {
        rows[3].value = name;
        count = 4;
    }
    try tui.render.keyValue(io, stdout, rows[0..count]);
    try stdout.writeAll("\n");
}

fn printSessionEnd(io: std.Io, stdout: anytype, result: supervisor.SessionResult, is_first_session: bool) !void {
    const code = result.exitCode();
    if (code == 0) {
        // Dynamic success line: explicit gated pattern (no alloc, respects useColor).
        // Uses Glyph for the checkmark (eliminates prior duplication).
        try stdout.writeAll("\n");
        if (style.useColor(io, stdout)) {
            try stdout.writeAll(style.Style.green);
            try stdout.print("{s} Session ended cleanly (exit {d})\n", .{ style.Glyph.check, code });
            try stdout.writeAll(style.Style.reset);
        } else {
            try stdout.print("{s} Session ended cleanly (exit {d})\n", .{ style.Glyph.check, code });
        }
    } else {
        try stdout.print("\n{s} Session ended with exit code {d}\n", .{ style.Glyph.cross, code });
    }
    if (is_first_session and code == 0) {
        // First-run celebration (static emotional text) routed through maybeColor + Glyph.
        // Demonstrates the warm path using the color helper (review gap closure).
        try stdout.writeAll("\n");
        try style.maybeColor(
            io,
            stdout,
            style.Style.green,
            style.Glyph.party ++ " Welcome to Orca! Your first protected session completed successfully.\n" ++
                "   Next: run `orca replay --session last` to review what happened.",
        );
        try stdout.writeAll("\n");
    }
}

/// Render the rich "guardian block" for a denied command to a human-facing
/// writer (stderr). Composes the `tui` design-system primitives:
///
///   ✗  Orca blocked a command            (callout .danger header)
///   ┌──────────────────────────────┐
///   │ ✗  <command>                 │     (panel, command as headline)
///   ├──────────────────────────────┤
///   │ Why        <plain-english>   │
///   │ Rule       <rule_id or —>    │
///   │ Policy     <path> · mode <m> │
///   └──────────────────────────────┘
///     Risk   ███████░░░░  <label>        (standalone meter — colour-safe)
///   Safe alternatives               (when derivable from command shape)
///     → <alt>  (<note>)
///   If this is intentional
///     → edit .orca/policy.yaml …
///     → orca policy explain command "…"
///
/// Graceful degrade: when `rule_id` is null (fail-closed / user-denial paths) or
/// not in the reason table, a generic reason + medium risk meter are used and
/// safe alternatives still derive from the command shape when possible.
///
/// This is presentation only — it never changes the decision, audit output, or
/// exit code. `--json`/robot output never reaches here.
fn renderDenyBlock(
    io: std.Io,
    stdout: anytype,
    allocator: std.mem.Allocator,
    command_argv: []const []const u8,
    rule_id: ?[]const u8,
    policy_path: ?[]const u8,
    policy_mode: []const u8,
) !void {
    // Header.
    try stdout.writeAll("\n");
    try tui.render.callout(io, stdout, .danger, "Orca blocked a command", "");
    try stdout.writeAll("\n");

    // Compose panel body lines (text-only — safe for the panel's width padding).
    // The coloured risk meter is rendered separately below to avoid ANSI codes
    // inside the padded panel body.
    var body: std.ArrayList([]const u8) = .empty;
    defer {
        for (body.items) |line| allocator.free(line);
        body.deinit(allocator);
    }

    const reason_text = if (rule_id) |rid| tui.reasons.reasonForRule(rid) else "Matched a deny rule in your Orca policy.";
    try body.append(allocator, try std.fmt.allocPrint(allocator, "Why        {s}", .{reason_text}));

    if (rule_id) |rid| {
        try body.append(allocator, try std.fmt.allocPrint(allocator, "Rule       {s}", .{rid}));
    } else {
        try body.append(allocator, try allocator.dupe(u8, "Rule       —"));
    }
    try body.append(allocator, try std.fmt.allocPrint(allocator, "Policy     {s} · mode {s}", .{ policy_path orelse "built-in", policy_mode }));

    // Panel title = the denied command, prefixed with the deny glyph.
    const command_display = try intercept.commands.displayArgvAlloc(allocator, command_argv);
    defer allocator.free(command_display);
    const title = try std.fmt.allocPrint(allocator, "✗  {s}", .{command_display});
    defer allocator.free(title);
    try tui.render.panel(io, stdout, title, body.items);
    try stdout.writeAll("\n");

    // Risk meter (standalone — colour-safe; degrades to plain on non-TTY).
    const risk = if (rule_id) |rid| tui.reasons.riskForRule(rid) else .medium;
    try stdout.writeAll("  ");
    try tui.theme.paint(io, stdout, .muted, "Risk   ");
    try tui.render.meter(io, stdout, tui.reasons.riskFraction(risk), tui.reasons.riskLabel(risk));
    try stdout.writeAll("\n\n");

    // Safe alternatives (derived from command shape; may be empty).
    const alts = try tui.reasons.safeAlternatives(allocator, command_display);
    defer {
        for (alts) |a| allocator.free(a.command);
        allocator.free(alts);
    }
    if (alts.len > 0) {
        try tui.theme.paintBold(io, stdout, .info, "  Safe alternatives");
        try stdout.writeAll("\n");
        for (alts) |a| {
            try stdout.writeAll("  → ");
            try tui.theme.paint(io, stdout, .text_bright, a.command);
            try stdout.print("  ({s})\n", .{a.note});
        }
        try stdout.writeAll("\n");
    }

    // "If this is intentional" footer — power-user escape hatches.
    try tui.theme.paintBold(io, stdout, .muted, "  If this is intentional");
    try stdout.writeAll("\n");
    try stdout.writeAll("  → edit .orca/policy.yaml to add an exception\n");
    try stdout.print("  → orca policy explain command \"{s}\"\n", .{command_display});
    try stdout.writeAll("\n");
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

/// Returns true if the workspace has no prior .orca/sessions/ entries.
/// Checked *before* the current session creates its directory so the first-run
/// celebration can be emitted exactly once.
///
/// NOTE: This is best-effort. A concurrent process may create a session dir
/// between the check and the current session's creation, or the user may have
/// manually cleaned sessions while keeping the workspace. The celebration is
/// a warm UX nicety — occasional false positives are acceptable.
fn isFirstSession(io: std.Io, allocator: std.mem.Allocator, workspace_root: []const u8) bool {
    const sessions_dir = std.fs.path.join(allocator, &.{ workspace_root, ".orca", "sessions" }) catch return true;
    defer allocator.free(sessions_dir);

    var dir = std.Io.Dir.cwd().openDir(io, sessions_dir, .{ .iterate = true }) catch return true;
    defer dir.close(io);

    var it = dir.iterate();
    while (it.next(io) catch return true) |entry| {
        if (entry.kind == .directory) {
            // Any real session dir means this is not the user's first
            return false;
        }
    }
    return true;
}

test "run rejects missing child command" {
    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try command(std.testing.io, &.{"--"}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.usage, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "missing command") != null);
    // TDD: warm multi-line error message with examples (foundation UX)
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "Example:") != null);
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "orca run -- echo") != null);
}

test "run rejects child command without separator" {
    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try command(std.testing.io, &.{"echo"}, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.usage, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "expected '--'") != null);
    // TDD: warm multi-line error message with examples + help pointer (foundation UX)
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "Example:") != null);
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "orca help run") != null);
}

test "run reports missing command usefully" {
    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try commandForTest(&.{ "--", "orca-definitely-missing-command" }, &stdout_writer, &stderr_writer, .ignore);
    try std.testing.expectEqual(exit_codes.general, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "command not found") != null);
}

pub fn commandForTest(argv: []const []const u8, stdout: anytype, stderr: anytype, stdio: supervisor.StdioBehavior) !u8 {
    return commandForTestWithShellEvaluator(argv, stdout, stderr, stdio, null);
}

pub fn commandForTestWithShellEvaluator(argv: []const []const u8, stdout: anytype, stderr: anytype, stdio: supervisor.StdioBehavior, shell_evaluator: ?shell_eval.ShellCommandEvaluatorFn) !u8 {
    return commandWithStdioAndEnv(std.testing.io, argv, stdout, stderr, stdio, false, null, shell_evaluator);
}

pub fn commandForGuardTestWithShellEvaluator(argv: []const []const u8, stdout: anytype, stderr: anytype, stdio: supervisor.StdioBehavior, shell_evaluator: ?shell_eval.ShellCommandEvaluatorFn) !u8 {
    return commandWithStdioAndEnv(std.testing.io, argv, stdout, stderr, stdio, true, null, shell_evaluator);
}

fn commandForTestWithEnv(argv: []const []const u8, stdout: anytype, stderr: anytype, stdio: supervisor.StdioBehavior, current_env: *const std.process.Environ.Map) !u8 {
    return commandForTestWithEnvAndShellEvaluator(argv, stdout, stderr, stdio, current_env, shell_eval.mockDaemonAllowEvaluator);
}

fn commandForTestWithEnvAndShellEvaluator(argv: []const []const u8, stdout: anytype, stderr: anytype, stdio: supervisor.StdioBehavior, current_env: *const std.process.Environ.Map, shell_evaluator: ?shell_eval.ShellCommandEvaluatorFn) !u8 {
    return commandWithStdioAndEnv(std.testing.io, argv, stdout, stderr, stdio, true, current_env, shell_evaluator);
}

test "run accepts policy path and uses policy mode when mode is not explicit" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    {
        const file = try tmp.dir.createFile(std.testing.io, "strict.yaml", .{});
        defer file.close(std.testing.io);
        try file.writeStreamingAll(std.testing.io, policy.presets.text(.strict));
    }
    const path = try tmp.dir.realPathFileAlloc(std.testing.io, "strict.yaml", std.testing.allocator);
    defer std.testing.allocator.free(path);

    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try commandForTestWithShellEvaluator(&.{ "--policy", path, "--", "zig", "version" }, &stdout_writer, &stderr_writer, .ignore, shell_eval.mockDaemonAllowEvaluator);
    try std.testing.expectEqual(exit_codes.success, code);
    // Phase 2: printSessionStart renders Mode via the tui key-value grid (label
    // "Mode", value = mode string). The exact padded column format is owned by
    // tui.render.keyValue; assert the mode value + label are present.
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "Mode") != null);
    try std.testing.expect(std.mem.indexOf(u8, stdout_writer.buffered(), "strict") != null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "run rejects inherit-env when selected policy disallows it" {
    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try commandForTest(&.{ "--policy", "policies/strict.yaml", "--inherit-env", "--", "zig", "version" }, &stdout_writer, &stderr_writer, .ignore);
    try std.testing.expectEqual(exit_codes.general, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "--inherit-env is not allowed") != null);
}

test "run accepts secretless option" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try commandForTestWithShellEvaluator(&.{ "--secretless", "--", "true" }, &stdout_writer, &stderr_writer, .ignore, shell_eval.mockDaemonAllowEvaluator);
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "run secretless replaces child env and keeps raw secret out of audit artifacts" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    {
        const policy_file = try tmp.dir.createFile(std.testing.io, "policy.yaml", .{});
        defer policy_file.close(std.testing.io);
        try policy_file.writeStreamingAll(std.testing.io,
            \\version: 1
            \\mode: observe
            \\env:
            \\  inherit: true
        );
    }
    const policy_path = try tmp.dir.realPathFileAlloc(std.testing.io, "policy.yaml", std.testing.allocator);
    defer std.testing.allocator.free(policy_path);
    {
        const script = try tmp.dir.createFile(std.testing.io, "dump-env.sh", .{});
        defer script.close(std.testing.io);
        try script.writeStreamingAll(std.testing.io,
            \\#!/bin/sh
            \\printf '%s' "$GITHUB_TOKEN" > child-env.txt
            \\
        );
        try tmp.dir.setFilePermissions(std.testing.io, "dump-env.sh", @enumFromInt(0o755), .{});
    }

    var current = std.process.Environ.Map.init(std.testing.allocator);
    defer current.deinit();
    const path_env = if (std.c.getenv("PATH")) |path| std.mem.span(path) else "/usr/bin:/bin:/usr/sbin:/sbin";
    try current.put("PATH", path_env);
    try current.put("GITHUB_TOKEN", "ghp_fakeSyntheticTokenValue1234567890");

    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [2048]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try commandForTestWithEnv(&.{ "--workspace", root, "--policy", policy_path, "--secretless", "--inherit-env", "--", "./dump-env.sh" }, &stdout_writer, &stderr_writer, .ignore, &current);
    try std.testing.expectEqual(exit_codes.success, code);

    const child_env = try tmp.dir.readFileAlloc(std.testing.io, "child-env.txt", std.testing.allocator, .limited(512));
    defer std.testing.allocator.free(child_env);
    try std.testing.expect(std.mem.startsWith(u8, child_env, "orca-secret://local-dummy/env/GITHUB_TOKEN/"));
    try std.testing.expect(std.mem.indexOf(u8, child_env, "ghp_fakeSyntheticTokenValue") == null);

    const events = try readLastEvents(std.testing.allocator, root);
    defer std.testing.allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"type\":\"secret_redacted\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "ghp_fakeSyntheticTokenValue") == null);
}

test "run command guard denies ci ask without prompting and audits command events" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [2048]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try commandForGuardTestWithShellEvaluator(&.{ "--workspace", root, "--mode", "ci", "--", "npm", "install", "OPENAI_API_KEY=sk-fakeSyntheticOpenAIKey1234567890" }, &stdout_writer, &stderr_writer, .inherit, shell_eval.mockDaemonDenyEvaluator);
    try std.testing.expectEqual(exit_codes.denial, code);
    // Phase 1 UX: rich guardian block replaces the flat "command denied" line.
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "Orca blocked") != null);
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "✗") != null);

    const events = try readLastEvents(std.testing.allocator, root);
    defer std.testing.allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"type\":\"command_attempt\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"type\":\"command_denied\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "sk-fakeSyntheticOpenAIKey") == null);
    try std.testing.expect(std.mem.indexOf(u8, events, "shell command (redacted)") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"decision_source\":\"rust-daemon\"") != null);
}

test "run command guard allows safe command and creates session shim directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [2048]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try commandForGuardTestWithShellEvaluator(&.{ "--workspace", root, "--", "true" }, &stdout_writer, &stderr_writer, .inherit, shell_eval.mockDaemonAllowEvaluator);
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());

    const session_id = try readLastSessionId(std.testing.allocator, root);
    defer std.testing.allocator.free(session_id);
    const shim_path = try std.fs.path.join(std.testing.allocator, &.{ root, ".orca", "sessions", session_id, "shims", "git" });
    defer std.testing.allocator.free(shim_path);
    try std.Io.Dir.cwd().access(std.testing.io, shim_path, .{});

    const events = try readLastEvents(std.testing.allocator, root);
    defer std.testing.allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"type\":\"command_allowed\"") != null);
}

test "run command guard denies destructive command before spawn" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [2048]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try commandForGuardTestWithShellEvaluator(&.{ "--workspace", root, "--", "rm", "-rf", "/" }, &stdout_writer, &stderr_writer, .inherit, shell_eval.mockDaemonDenyEvaluator);
    try std.testing.expectEqual(exit_codes.denial, code);
    const events = try readLastEvents(std.testing.allocator, root);
    defer std.testing.allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"type\":\"command_denied\"") != null);
}

test "run no-network sets network mode off and audits denied network state" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [2048]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try commandForGuardTestWithShellEvaluator(&.{ "--workspace", root, "--no-network", "--", "true" }, &stdout_writer, &stderr_writer, .inherit, shell_eval.mockDaemonAllowEvaluator);
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
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [2048]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try commandForGuardTestWithShellEvaluator(&.{ "--workspace", root, "--allow-network", "https://api.github.com/repos?token=sk-fakeSyntheticOpenAIKey1234567890", "--", "true" }, &stdout_writer, &stderr_writer, .inherit, shell_eval.mockDaemonAllowEvaluator);
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
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [2048]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try commandForTestWithShellEvaluator(&.{ "--workspace", root, "--", "/bin/sh", "-c", "env > backend-env.txt" }, &stdout_writer, &stderr_writer, .ignore, shell_eval.mockDaemonAllowEvaluator);
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());

    const written = try tmp.dir.readFileAlloc(std.testing.io, "backend-env.txt", std.testing.allocator, .limited(8192));
    defer std.testing.allocator.free(written);
    try std.testing.expect(std.mem.indexOf(u8, written, "ORCA_BACKEND=") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "ORCA_BACKEND_ENV_FILTERING=") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "ORCA_BACKEND_PATH_STAGING=") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "ORCA_BACKEND_SHELL_WRAPPING=") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "ORCA_BACKEND_PATH_SHIMS=") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "ORCA_BACKEND_STRONG_SANDBOX=") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "ORCA_BACKEND_PROCESS_SUPERVISION=") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "ORCA_BACKEND_NETWORK_OBSERVE=") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "ORCA_BACKEND_NETWORK_ENFORCEMENT=") != null);
}

test "run proxy backend injects proxy environment and satisfies network enforcement requirement" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    {
        const policy_file = try tmp.dir.createFile(std.testing.io, "policy.yaml", .{});
        defer policy_file.close(std.testing.io);
        try policy_file.writeStreamingAll(std.testing.io,
            \\version: 1
            \\mode: observe
            \\env:
            \\  inherit: true
            \\commands:
            \\  allow:
            \\    - "/bin/sh *"
        );
    }
    const policy_path = try tmp.dir.realPathFileAlloc(std.testing.io, "policy.yaml", std.testing.allocator);
    defer std.testing.allocator.free(policy_path);

    var current = std.process.Environ.Map.init(std.testing.allocator);
    defer current.deinit();
    const path_env = if (std.c.getenv("PATH")) |path| std.mem.span(path) else "/usr/bin:/bin:/usr/sbin:/sbin";
    try current.put("PATH", path_env);

    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [2048]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try commandForTestWithEnvAndShellEvaluator(&.{ "--workspace", root, "--policy", policy_path, "--network-backend", "proxy", "--require-backend", "network_enforce", "--", "/bin/sh", "-c", "env > proxy-env.txt" }, &stdout_writer, &stderr_writer, .ignore, &current, shell_eval.mockDaemonAllowEvaluator);
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());

    const written = try tmp.dir.readFileAlloc(std.testing.io, "proxy-env.txt", std.testing.allocator, .limited(8192));
    defer std.testing.allocator.free(written);
    try std.testing.expect(std.mem.indexOf(u8, written, "HTTP_PROXY=http://127.0.0.1:") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "HTTPS_PROXY=http://127.0.0.1:") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "ALL_PROXY=http://127.0.0.1:") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "ORCA_NETWORK_ENFORCEMENT=proxy-mediated") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "ORCA_PROXY_HTTPS_VISIBILITY=host-port-only") != null);

    const events = try readLastEvents(std.testing.allocator, root);
    defer std.testing.allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"type\":\"network_proxy_start\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"type\":\"network_proxy_stop\"") != null);
}

test "run rejects unknown network backend" {
    var stdout_buf: [512]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try command(std.testing.io, &.{ "--network-backend", "magic", "--", "true" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.usage, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "unsupported network backend") != null);
}

test "run require-backend fails closed when requested feature is unavailable" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [2048]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try command(std.testing.io, &.{ "--workspace", root, "--mode", "ci", "--require-backend", "network_enforce", "--", "true" }, &stdout_writer, &stderr_writer);
    try std.testing.expectEqual(exit_codes.unsupported, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "required backend feature is unavailable") != null);

    const events = try readLastEvents(std.testing.allocator, root);
    defer std.testing.allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"type\":\"backend_capability\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "required backend feature unavailable") != null);
}

test "run shell evaluation forwards command and cwd to daemon Evaluate" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    shell_eval.test_last_evaluate_command = null;
    shell_eval.test_last_evaluate_cwd = null;

    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [2048]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    // Keep this forwarding test independent of the child/shim lifecycle. `git`
    // is one of Orca's generated shims, so launching `git status` here also
    // exercised a nested test-binary process and intermittently surfaced its
    // signal termination as exit code 5. `true` is not shimmed and keeps this
    // test focused on the Evaluate command/cwd boundary.
    const code = try commandForGuardTestWithShellEvaluator(&.{ "--workspace", root, "--", "true" }, &stdout_writer, &stderr_writer, .ignore, shell_eval.mockDaemonAllowEvaluator);
    try std.testing.expectEqual(exit_codes.success, code);
    try std.testing.expectEqualStrings("true", shell_eval.test_last_evaluate_command.?);
    try std.testing.expectEqualStrings(root, shell_eval.test_last_evaluate_cwd.?);
}

test "run daemon unavailable denies shell command" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [2048]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try commandForGuardTestWithShellEvaluator(&.{ "--workspace", root, "--", "git", "status" }, &stdout_writer, &stderr_writer, .ignore, shell_eval.mockDaemonUnavailableEvaluator);
    try std.testing.expectEqual(exit_codes.denial, code);
    // Phase 1 UX: rich guardian block (graceful-degrade path — no rule id).
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "Orca blocked") != null);
}

test "run daemon protocol mismatch denies shell command" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [2048]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try commandForGuardTestWithShellEvaluator(&.{ "--workspace", root, "--", "git", "status" }, &stdout_writer, &stderr_writer, .ignore, shell_eval.mockDaemonProtocolMismatchEvaluator);
    try std.testing.expectEqual(exit_codes.denial, code);
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "Orca blocked") != null or std.mem.indexOf(u8, stderr_writer.buffered(), "command denied") != null);
}

fn readLastSessionId(allocator: std.mem.Allocator, root: []const u8) ![]u8 {
    const last_path = try std.fs.path.join(allocator, &.{ root, ".orca", "last" });
    defer allocator.free(last_path);
    const text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, last_path, allocator, .limited(core.limits.max_session_id_len + 2));
    defer allocator.free(text);
    return try allocator.dupe(u8, std.mem.trim(u8, text, " \t\r\n"));
}

fn readLastEvents(allocator: std.mem.Allocator, root: []const u8) ![]u8 {
    const session_id = try readLastSessionId(allocator, root);
    defer allocator.free(session_id);
    const events_path = try std.fs.path.join(allocator, &.{ root, ".orca", "sessions", session_id, "events.jsonl" });
    defer allocator.free(events_path);
    return try std.Io.Dir.cwd().readFileAlloc(std.testing.io, events_path, allocator, .limited(64 * 1024));
}

fn writeLastPointerNoMakePath(allocator: std.mem.Allocator, workspace_root: []const u8, session_id: []const u8) !void {
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    const last_path = try std.fs.path.join(allocator, &.{ workspace_root, ".orca", "last" });
    defer allocator.free(last_path);
    const file = try std.Io.Dir.cwd().createFile(io, last_path, .{ .truncate = true });
    defer file.close(io);
    try file.writeStreamingAll(io, session_id);
    try file.writeStreamingAll(io, "\n");
    try file.sync(io);
}

// ---------------------------------------------------------------------------
// TDD: first successful run celebration (written FIRST — RED, foundation work)
// These exercise isFirstSession + the celebration branch in printSessionEnd.
// ---------------------------------------------------------------------------

test "first successful run prints celebration" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    // Fresh workspace: no .orca/sessions yet → should be first
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try commandForTestWithShellEvaluator(&.{ "--workspace", root, "--", "echo", "hi-from-first" }, &stdout_writer, &stderr_writer, .inherit, shell_eval.mockDaemonAllowEvaluator);
    try std.testing.expectEqual(exit_codes.success, code);
    const out = stdout_writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, out, "Welcome to Orca!") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "replay --session last") != null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "subsequent runs do not print celebration" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    // Pre-create a fake prior session dir inside the temp workspace
    try tmp.dir.createDirPath(std.testing.io, ".orca/sessions/2026-01-01T00-00-00Z_aaaa");

    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [512]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try commandForTestWithShellEvaluator(&.{ "--workspace", root, "--", "echo", "hi-from-second" }, &stdout_writer, &stderr_writer, .inherit, shell_eval.mockDaemonAllowEvaluator);
    try std.testing.expectEqual(exit_codes.success, code);
    const out = stdout_writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, out, "Welcome to Orca!") == null);
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

// ---------------------------------------------------------------------------
// TDD: Phase 1 — rich guardian block on deny (written FIRST → RED → GREEN).
// These exercise renderDenyBlock via the real run.zig deny path. Fixed-buffer
// writers + std.testing.io force theme.active() to .none, so assertions hold
// against the plain-text degrade path (the colour path is covered by theme.zig).
// ---------------------------------------------------------------------------

test "deny block renders rich guardian block for rm -rf /" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try commandForGuardTestWithShellEvaluator(&.{ "--workspace", root, "--", "rm", "-rf", "/" }, &stdout_writer, &stderr_writer, .inherit, shell_eval.mockDaemonDenyEvaluator);
    try std.testing.expectEqual(exit_codes.denial, code);
    const err = stderr_writer.buffered();

    // Hero header.
    try std.testing.expect(std.mem.indexOf(u8, err, "✗") != null);
    try std.testing.expect(std.mem.indexOf(u8, err, "Orca blocked") != null);
    // The denied command appears as the panel headline.
    try std.testing.expect(std.mem.indexOf(u8, err, "rm -rf /") != null);
    // Why / Rule / Policy rows inside the panel.
    try std.testing.expect(std.mem.indexOf(u8, err, "Why") != null);
    try std.testing.expect(std.mem.indexOf(u8, err, "Rule") != null);
    try std.testing.expect(std.mem.indexOf(u8, err, "Policy") != null);
    // Risk meter label is present.
    try std.testing.expect(std.mem.indexOf(u8, err, "Risk") != null);
    // Safe alternatives derived from `rm -rf /` shape.
    try std.testing.expect(std.mem.indexOf(u8, err, "Safe alternatives") != null);
    try std.testing.expect(std.mem.indexOf(u8, err, "./build") != null);
    // "If this is intentional" footer with a real escape hatch.
    try std.testing.expect(std.mem.indexOf(u8, err, "If this is intentional") != null);
    try std.testing.expect(std.mem.indexOf(u8, err, "orca policy explain") != null);
    // The old flat line is gone.
    try std.testing.expect(std.mem.indexOf(u8, err, "command denied by command guard") == null);
}

test "deny block includes reasonForRule text when rule id is known" {
    // reasonForRule is driven by the daemon's pattern_name. The mock deny
    // evaluator returns pattern_name "destructive_rm" (not in the table), so it
    // exercises the graceful-degrade fallback. Assert the fallback text appears.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try commandForGuardTestWithShellEvaluator(&.{ "--workspace", root, "--", "rm", "-rf", "/" }, &stdout_writer, &stderr_writer, .inherit, shell_eval.mockDaemonDenyEvaluator);
    try std.testing.expectEqual(exit_codes.denial, code);
    const err = stderr_writer.buffered();
    // The captured rule id ("destructive_rm") is shown in the Rule row.
    try std.testing.expect(std.mem.indexOf(u8, err, "destructive_rm") != null);
    // Unknown rule → fallback reason text from reasonForRule.
    try std.testing.expect(std.mem.indexOf(u8, err, "deny rule") != null);
}

test "deny block graceful-degrades without rule id (daemon unavailable)" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    // mockDaemonUnavailableEvaluator → fail-closed deny with no rule id.
    const code = try commandForGuardTestWithShellEvaluator(&.{ "--workspace", root, "--", "git", "status" }, &stdout_writer, &stderr_writer, .ignore, shell_eval.mockDaemonUnavailableEvaluator);
    try std.testing.expectEqual(exit_codes.denial, code);
    const err = stderr_writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, err, "Orca blocked") != null);
    try std.testing.expect(std.mem.indexOf(u8, err, "✗") != null);
    // Rule row shows the em-dash placeholder when no rule id is available.
    try std.testing.expect(std.mem.indexOf(u8, err, "Rule") != null);
    // No crash; exit code unchanged.
}

test "deny block keeps exit code and does not print the flat line" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);

    var stdout_buf: [2048]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_writer: std.Io.Writer = .fixed(&stdout_buf);
    var stderr_writer: std.Io.Writer = .fixed(&stderr_buf);

    const code = try commandForGuardTestWithShellEvaluator(&.{ "--workspace", root, "--", "rm", "-rf", "/" }, &stdout_writer, &stderr_writer, .inherit, shell_eval.mockDaemonDenyEvaluator);
    // Invariant: exit code stays exit_codes.denial.
    try std.testing.expectEqual(exit_codes.denial, code);
    // The flat one-liner is fully replaced.
    try std.testing.expect(std.mem.indexOf(u8, stderr_writer.buffered(), "orca run: command denied by command guard.\n") == null);
}
