const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const version = std.mem.trim(u8, @embedFile("VERSION"), " \n\r\t");
    const commit = b.option([]const u8, "commit", "Source commit metadata") orelse "unknown";
    const build_date = b.option([]const u8, "build-date", "UTC build date metadata") orelse "unknown";

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", version);
    build_options.addOption([]const u8, "commit", commit);
    build_options.addOption([]const u8, "build_date", build_date);
    const build_options_mod = build_options.createModule();

    const core_schema_documents = b.addOptions();
    core_schema_documents.addOption([]const u8, "policy_v1", @embedFile("schemas/policy-v1.json"));
    core_schema_documents.addOption([]const u8, "event_v1", @embedFile("schemas/event-v1.json"));
    core_schema_documents.addOption([]const u8, "mcp_manifest_v1", @embedFile("schemas/mcp-manifest-v1.json"));
    const core_schema_documents_mod = core_schema_documents.createModule();

    const core_impl_mod = b.addModule("orca_core_impl", .{
        .root_source_file = b.path("src/core_package.zig"),
        .target = target,
        .optimize = optimize,
    });

    const orca_core_mod = b.addModule("orca_core", .{
        .root_source_file = b.path("packages/core/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core_impl", .module = core_impl_mod },
            .{ .name = "core_schema_documents", .module = core_schema_documents_mod },
        },
    });

    const orca_mod = b.addModule("orca", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "orca_core", .module = orca_core_mod },
            .{ .name = "build_options", .module = build_options_mod },
        },
    });

    const orca_cli_mod = b.addModule("orca_cli", .{
        .root_source_file = b.path("packages/cli/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "orca", .module = orca_mod },
            .{ .name = "orca_core", .module = orca_core_mod },
            .{ .name = "build_options", .module = build_options_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "orca",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "orca", .module = orca_mod },
                .{ .name = "build_options", .module = build_options_mod },
            },
        }),
    });

    b.installArtifact(exe);
    const install_orca = b.addInstallArtifact(exe, .{});
    const install_orca_step = b.step("install-orca", "Install Orca CLI only");
    install_orca_step.dependOn(&install_orca.step);

    const run_step = b.step("run", "Run the Orca CLI");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    run_step.dependOn(&run_cmd.step);

    const lib_tests = b.addTest(.{
        .root_module = orca_mod,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const core_package_tests = b.addTest(.{
        .root_module = orca_core_mod,
    });
    const run_core_package_tests = b.addRunArtifact(core_package_tests);

    const core_contract_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("packages/core/tests/contract.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "orca_core", .module = orca_core_mod },
            },
        }),
    });
    const run_core_contract_tests = b.addRunArtifact(core_contract_tests);

    const cli_package_tests = b.addTest(.{
        .root_module = orca_cli_mod,
    });
    const run_cli_package_tests = b.addRunArtifact(cli_package_tests);

    const cli_contract_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("packages/cli/tests/contract.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "orca_cli", .module = orca_cli_mod },
            },
        }),
    });
    const run_cli_contract_tests = b.addRunArtifact(cli_contract_tests);

    const phase25_hardening_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/phase25_cli_hardening.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "orca", .module = orca_mod },
            },
        }),
    });
    const run_phase25_hardening_tests = b.addRunArtifact(phase25_hardening_tests);

    const phase36_codex_plugin_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/phase36_codex_plugin.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_phase36_codex_plugin_tests = b.addRunArtifact(phase36_codex_plugin_tests);

    const phase37_claude_plugin_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/phase37_claude_plugin.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_phase37_claude_plugin_tests = b.addRunArtifact(phase37_claude_plugin_tests);

    const phase38_plugin_security_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/phase38_plugin_security_and_compatibility.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_phase38_plugin_security_tests = b.addRunArtifact(phase38_plugin_security_tests);

    const phase39_openclaw_plugin_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/phase39_openclaw_plugin.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_phase39_openclaw_plugin_tests = b.addRunArtifact(phase39_openclaw_plugin_tests);

    const phase43_hermes_plugin_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/phase43_hermes_plugin.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_phase43_hermes_plugin_tests = b.addRunArtifact(phase43_hermes_plugin_tests);

    const setup_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/setup.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "orca", .module = orca_mod },
                .{ .name = "orca_core", .module = orca_core_mod },
            },
        }),
    });
    const run_setup_tests = b.addRunArtifact(setup_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_exe_tests.step);
    test_step.dependOn(&run_core_package_tests.step);
    test_step.dependOn(&run_core_contract_tests.step);
    test_step.dependOn(&run_cli_package_tests.step);
    test_step.dependOn(&run_cli_contract_tests.step);
    test_step.dependOn(&run_phase25_hardening_tests.step);
    test_step.dependOn(&run_phase36_codex_plugin_tests.step);
    test_step.dependOn(&run_phase37_claude_plugin_tests.step);
    test_step.dependOn(&run_phase38_plugin_security_tests.step);
    test_step.dependOn(&run_phase39_openclaw_plugin_tests.step);
    test_step.dependOn(&run_phase43_hermes_plugin_tests.step);
    test_step.dependOn(&run_setup_tests.step);

    const fuzz_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/fuzz/security_mutation.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "orca", .module = orca_mod },
            },
        }),
    });
    const run_fuzz_tests = b.addRunArtifact(fuzz_tests);
    const fuzz_step = b.step("fuzz", "Run deterministic security mutation tests");
    fuzz_step.dependOn(&run_fuzz_tests.step);
    test_step.dependOn(&run_fuzz_tests.step);

    const windows_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .windows,
    });
    const windows_mod = b.addModule("orca-windows-check", .{
        .root_source_file = b.path("src/root.zig"),
        .target = windows_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "orca_core", .module = orca_core_mod },
            .{ .name = "build_options", .module = build_options_mod },
        },
    });
    const windows_exe = b.addExecutable(.{
        .name = "orca-windows-check",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = windows_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "orca", .module = windows_mod },
                .{ .name = "build_options", .module = build_options_mod },
            },
        }),
    });
    const check_windows_step = b.step("check-windows", "Compile Orca for Windows without running it");
    check_windows_step.dependOn(&windows_exe.step);
}
