const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const version = b.option([]const u8, "version", "Aegis version metadata") orelse "1.1.0";
    const commit = b.option([]const u8, "commit", "Source commit metadata") orelse "unknown";
    const build_date = b.option([]const u8, "build-date", "UTC build date metadata") orelse "unknown";

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", version);
    build_options.addOption([]const u8, "commit", commit);
    build_options.addOption([]const u8, "build_date", build_date);
    const build_options_mod = build_options.createModule();

    const aegis_mod = b.addModule("aegis", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "build_options", .module = build_options_mod },
        },
    });

    const aegis_core_mod = b.addModule("aegis_core", .{
        .root_source_file = b.path("packages/core/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "aegis", .module = aegis_mod },
        },
    });

    const aegis_cli_mod = b.addModule("aegis_cli", .{
        .root_source_file = b.path("packages/cli/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "aegis", .module = aegis_mod },
            .{ .name = "aegis_core", .module = aegis_core_mod },
            .{ .name = "build_options", .module = build_options_mod },
        },
    });

    const aegis_edge_mod = b.addModule("aegis_edge", .{
        .root_source_file = b.path("packages/edge/src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "aegis_core", .module = aegis_core_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "aegis",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "aegis", .module = aegis_mod },
                .{ .name = "build_options", .module = build_options_mod },
            },
        }),
    });

    b.installArtifact(exe);

    const edge_exe = b.addExecutable(.{
        .name = "aegis-edge",
        .root_module = b.createModule(.{
            .root_source_file = b.path("packages/edge/src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "aegis_edge", .module = aegis_edge_mod },
            },
        }),
    });

    b.installArtifact(edge_exe);

    const run_step = b.step("run", "Run the Aegis CLI");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    run_step.dependOn(&run_cmd.step);

    const lib_tests = b.addTest(.{
        .root_module = aegis_mod,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const core_package_tests = b.addTest(.{
        .root_module = aegis_core_mod,
    });
    const run_core_package_tests = b.addRunArtifact(core_package_tests);

    const core_contract_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("packages/core/tests/contract.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "aegis_core", .module = aegis_core_mod },
            },
        }),
    });
    const run_core_contract_tests = b.addRunArtifact(core_contract_tests);

    const cli_package_tests = b.addTest(.{
        .root_module = aegis_cli_mod,
    });
    const run_cli_package_tests = b.addRunArtifact(cli_package_tests);

    const cli_contract_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("packages/cli/tests/contract.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "aegis_cli", .module = aegis_cli_mod },
            },
        }),
    });
    const run_cli_contract_tests = b.addRunArtifact(cli_contract_tests);

    const edge_package_tests = b.addTest(.{
        .root_module = aegis_edge_mod,
    });
    const run_edge_package_tests = b.addRunArtifact(edge_package_tests);

    const edge_contract_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("packages/edge/tests/contract.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "aegis_edge", .module = aegis_edge_mod },
            },
        }),
    });
    const run_edge_contract_tests = b.addRunArtifact(edge_contract_tests);

    const edge_exe_tests = b.addTest(.{
        .root_module = edge_exe.root_module,
    });
    const run_edge_exe_tests = b.addRunArtifact(edge_exe_tests);

    const phase23_contract_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/phase23_contract.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "aegis_core", .module = aegis_core_mod },
                .{ .name = "aegis_edge", .module = aegis_edge_mod },
            },
        }),
    });
    const run_phase23_contract_tests = b.addRunArtifact(phase23_contract_tests);

    const phase25_hardening_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/phase25_cli_hardening.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "aegis", .module = aegis_mod },
            },
        }),
    });
    const run_phase25_hardening_tests = b.addRunArtifact(phase25_hardening_tests);

    const phase26_edge_domain_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/phase26_edge_domain.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "aegis_edge", .module = aegis_edge_mod },
            },
        }),
    });
    const run_phase26_edge_domain_tests = b.addRunArtifact(phase26_edge_domain_tests);

    const phase27_edge_policy_engine_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/phase27_edge_policy_engine.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "aegis_edge", .module = aegis_edge_mod },
            },
        }),
    });
    const run_phase27_edge_policy_engine_tests = b.addRunArtifact(phase27_edge_policy_engine_tests);

    const phase28_mavlink_gateway_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/phase28_mavlink_gateway.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "aegis_edge", .module = aegis_edge_mod },
            },
        }),
    });
    const run_phase28_mavlink_gateway_tests = b.addRunArtifact(phase28_mavlink_gateway_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_exe_tests.step);
    test_step.dependOn(&run_core_package_tests.step);
    test_step.dependOn(&run_core_contract_tests.step);
    test_step.dependOn(&run_cli_package_tests.step);
    test_step.dependOn(&run_cli_contract_tests.step);
    test_step.dependOn(&run_edge_package_tests.step);
    test_step.dependOn(&run_edge_contract_tests.step);
    test_step.dependOn(&run_edge_exe_tests.step);
    test_step.dependOn(&run_phase23_contract_tests.step);
    test_step.dependOn(&run_phase25_hardening_tests.step);
    test_step.dependOn(&run_phase26_edge_domain_tests.step);
    test_step.dependOn(&run_phase27_edge_policy_engine_tests.step);
    test_step.dependOn(&run_phase28_mavlink_gateway_tests.step);

    const fuzz_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/fuzz/security_mutation.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "aegis", .module = aegis_mod },
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
    const windows_mod = b.addModule("aegis-windows-check", .{
        .root_source_file = b.path("src/root.zig"),
        .target = windows_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "build_options", .module = build_options_mod },
        },
    });
    const windows_exe = b.addExecutable(.{
        .name = "aegis-windows-check",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = windows_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "aegis", .module = windows_mod },
                .{ .name = "build_options", .module = build_options_mod },
            },
        }),
    });
    const check_windows_step = b.step("check-windows", "Compile Aegis for Windows without running it");
    check_windows_step.dependOn(&windows_exe.step);
}
