const std = @import("std");

fn readFile(path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(std.testing.allocator, path, 1024 * 1024);
}

fn expectFile(path: []const u8) !void {
    std.fs.cwd().access(path, .{}) catch |err| {
        std.debug.print("missing required Phase 42 file: {s}\n", .{path});
        return err;
    };
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("expected Phase 42 text not found: {s}\n", .{needle});
        return error.ExpectedTextMissing;
    }
}

fn expectNotContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) != null) {
        std.debug.print("forbidden Phase 42 text found: {s}\n", .{needle});
        return error.ForbiddenTextFound;
    }
}

test "phase 42 go-to-market package includes required acquisition materials" {
    const required = [_][]const u8{
        "go_to_market/README.md",
        "go_to_market/30-day-plan.md",
        "go_to_market/30-day-checklist.md",
        "go_to_market/icp.md",
        "go_to_market/target-account-template.csv",
        "go_to_market/target-account-template.md",
        "go_to_market/qualification-framework.md",
        "go_to_market/landing-page-copy.md",
        "go_to_market/outreach/founder-email-1.md",
        "go_to_market/outreach/founder-email-2-followup.md",
        "go_to_market/outreach/founder-linkedin-message.md",
        "go_to_market/outreach/warm-intro-request.md",
        "go_to_market/outreach/post-demo-followup.md",
        "go_to_market/outreach/pilot-proposal-email.md",
        "go_to_market/calls/discovery-call-script.md",
        "go_to_market/calls/demo-call-script.md",
        "go_to_market/calls/technical-validation-call.md",
        "go_to_market/calls/safety-review-call.md",
        "go_to_market/calls/objections-and-answers.md",
        "go_to_market/pilots/paid-pilot-offer.md",
        "go_to_market/pilots/pilot-pricing-guidance.md",
        "go_to_market/pilots/pilot-close-plan.md",
        "go_to_market/pilots/pilot-mutual-action-plan.md",
        "go_to_market/pilots/pilot-success-scorecard.md",
        "go_to_market/launch/launch-checklist.md",
        "go_to_market/launch/announcement-draft.md",
        "go_to_market/launch/demo-video-script.md",
        "go_to_market/launch/founder-demo-talk-track.md",
        "go_to_market/launch/community-post-draft.md",
        "go_to_market/crm/crm-fields.md",
        "go_to_market/crm/pipeline-stages.md",
        "go_to_market/crm/daily-tracker-template.md",
        "go_to_market/crm/weekly-review-template.md",
        "go_to_market/metrics/acquisition-dashboard.md",
        "go_to_market/metrics/success-metrics.md",
        "go_to_market/safety/safety-claims-guide.md",
        "go_to_market/safety/claims-to-avoid.md",
        "go_to_market/safety/customer-boundary-language.md",
        "go_to_market/targeting/first-50-account-build-guide.md",
        "go_to_market/targeting/customer-safety-filter.md",
        "go_to_market/PHASE_42_OUTPUT_SUMMARY.md",
        "scripts/validate-go-to-market.sh",
    };
    for (required) |path| try expectFile(path);
}

test "phase 42 acquisition plan and ICP preserve customer-evaluation scope" {
    const plan = try readFile("go_to_market/30-day-plan.md");
    defer std.testing.allocator.free(plan);
    try expectContains(plan, "book 10 customer discovery/demo calls");
    try expectContains(plan, "secure 3 serious design partners");
    try expectContains(plan, "close 1 paid pilot");
    try expectContains(plan, "Days 1-3");
    try expectContains(plan, "Days 4-10");
    try expectContains(plan, "Days 11-20");
    try expectContains(plan, "Days 21-30");
    try expectContains(plan, "simulation/SITL/bench-preparation");

    const icp = try readFile("go_to_market/icp.md");
    defer std.testing.allocator.free(icp);
    try expectContains(icp, "10-300 employees");
    try expectContains(icp, "PX4");
    try expectContains(icp, "ArduPilot");
    try expectContains(icp, "MAVLink");
    try expectContains(icp, "ROS2");
    try expectContains(icp, "simulation/SITL");
    try expectContains(icp, "Avoid as first customers");
    try expectContains(icp, "weapons/kinetic");
    try expectContains(icp, "CTO");
    try expectContains(icp, "Head of Autonomy");
}

test "phase 42 outreach and calls are founder-led manual and safety-bounded" {
    const email = try readFile("go_to_market/outreach/founder-email-1.md");
    defer std.testing.allocator.free(email);
    try expectContains(email, "Safety firewall for autonomous drone agents");
    try expectContains(email, "20-minute call");
    try expectContains(email, "agent tries to send an unsafe command");
    try expectContains(email, "Aegis denies it");
    try expectContains(email, "not flight certification or a flight controller");
    try expectContains(email, "{{name}}");
    try expectNotContains(email, "automatically send");

    const discovery = try readFile("go_to_market/calls/discovery-call-script.md");
    defer std.testing.allocator.free(discovery);
    try expectContains(discovery, "Where does autonomy live in your stack?");
    try expectContains(discovery, "What commands can autonomy issue today?");
    try expectContains(discovery, "Do you run SITL?");
    try expectContains(discovery, "Do you have replayable evidence");

    const demo = try readFile("go_to_market/calls/demo-call-script.md");
    defer std.testing.allocator.free(demo);
    try expectContains(demo, "./zig-out/bin/edge demo run geofence-deny");
    try expectContains(demo, "./zig-out/bin/edge demo run disable-failsafe-deny");
    try expectContains(demo, "./zig-out/bin/edge demo run emergency-land");
    try expectContains(demo, "./zig-out/bin/edge demo run stale-telemetry-deny");
    try expectContains(demo, "./zig-out/bin/edge demo run data-exfil-deny");
    try expectContains(demo, "./zig-out/bin/edge proof generate --demo geofence-deny");
    try expectContains(demo, "./zig-out/bin/edge redteam --ci");
}

test "phase 42 pilot offer pricing and legal-ish materials are bounded" {
    const offer = try readFile("go_to_market/pilots/paid-pilot-offer.md");
    defer std.testing.allocator.free(offer);
    try expectContains(offer, "Edge Simulation/SITL Safety Pilot");
    try expectContains(offer, "2 weeks");
    try expectContains(offer, "one autonomy workflow");
    try expectContains(offer, "command surface inventory");
    try expectContains(offer, "safety-case report");
    try expectContains(offer, "out of scope");
    try expectContains(offer, "Template only - requires legal review");
    try expectContains(offer, "editable/internal guidance");

    const pricing = try readFile("go_to_market/pilots/pilot-pricing-guidance.md");
    defer std.testing.allocator.free(pricing);
    try expectContains(pricing, "free design partner vs paid pilot");
    try expectContains(pricing, "$2.5k-$10k");
    try expectContains(pricing, "$10k-$25k");
    try expectContains(pricing, "editable/internal guidance");
    try expectContains(pricing, "what to avoid promising");
}

test "phase 42 safety claims and targeting filters reject overclaims and unsafe customers" {
    const claims = try readFile("go_to_market/safety/claims-to-avoid.md");
    defer std.testing.allocator.free(claims);
    try expectContains(claims, "certified safe");
    try expectContains(claims, "guarantees safety");
    try expectContains(claims, "FAA approved");
    try expectContains(claims, "BVLOS-ready");
    try expectContains(claims, "flight-ready");
    try expectContains(claims, "replaces autopilot");
    try expectContains(claims, "detect-and-avoid");
    try expectContains(claims, "covers all MAVLink commands");

    const allowed = try readFile("go_to_market/safety/safety-claims-guide.md");
    defer std.testing.allocator.free(allowed);
    try expectContains(allowed, "simulation/SITL evidence");
    try expectContains(allowed, "policy enforcement in supported scenarios");
    try expectContains(allowed, "audit/replay evidence");
    try expectContains(allowed, "not certification");
    try expectContains(allowed, "not real-flight validation");
    try expectContains(allowed, "not autopilot replacement");

    const filter = try readFile("go_to_market/targeting/customer-safety-filter.md");
    defer std.testing.allocator.free(filter);
    try expectContains(filter, "weapons/kinetic drone use");
    try expectContains(filter, "real-flight shortcuts");
    try expectContains(filter, "bypass failsafes");
    try expectContains(filter, "simulation/SITL first");
}

test "phase 42 materials avoid fake secrets private contact data spam automation and positive overclaims" {
    const files = [_][]const u8{
        "go_to_market/README.md",
        "go_to_market/30-day-plan.md",
        "go_to_market/icp.md",
        "go_to_market/outreach/founder-email-1.md",
        "go_to_market/outreach/founder-email-2-followup.md",
        "go_to_market/outreach/founder-linkedin-message.md",
        "go_to_market/outreach/warm-intro-request.md",
        "go_to_market/outreach/post-demo-followup.md",
        "go_to_market/outreach/pilot-proposal-email.md",
        "go_to_market/calls/objections-and-answers.md",
        "go_to_market/pilots/paid-pilot-offer.md",
        "go_to_market/launch/announcement-draft.md",
        "go_to_market/landing-page-copy.md",
        "go_to_market/safety/customer-boundary-language.md",
        "go_to_market/targeting/customer-safety-filter.md",
        "go_to_market/PHASE_42_OUTPUT_SUMMARY.md",
    };
    for (files) |path| {
        const text = try readFile(path);
        defer std.testing.allocator.free(text);
        try expectNotContains(text, "BEGIN PRIVATE KEY");
        try expectNotContains(text, "ghp_");
        try expectNotContains(text, "sk-");
        try expectNotContains(text, "@example.com");
        try expectNotContains(text, "autopilot replacement");
        try expectNotContains(text, "detect-and-avoid system");
        try expectNotContains(text, "certified safe");
        try expectNotContains(text, "FAA approved");
        try expectNotContains(text, "BVLOS-ready");
        try expectNotContains(text, "real-flight-ready");
        try expectNotContains(text, "automated sender");
        try expectNotContains(text, "spam");
        try expectNotContains(text, "scrape private");
    }
}
