use std::process::Command;

fn orca_binary() -> std::path::PathBuf {
    let mut path = std::env::current_exe().unwrap();
    path.pop(); // deps
    path.pop(); // debug
    path.push("orca-daemon");
    path
}

fn run_hook_with_allowlist(command: &str, allowlist_content: &str) -> String {
    let temp_dir = tempfile::tempdir().unwrap();

    // Create a fake home dir for user config loading
    let home_dir = temp_dir.path().join("home");
    let user_config_dir = home_dir.join(".config/orca");
    std::fs::create_dir_all(&user_config_dir).unwrap();
    std::fs::write(user_config_dir.join("allowlist.toml"), allowlist_content).unwrap();

    let input = serde_json::json!({
        "tool_name": "Bash",
        "tool_input": {
            "command": command,
        }
    });

    let mut child = Command::new(orca_binary())
        .env("HOME", &home_dir)
        .env("XDG_CONFIG_HOME", home_dir.join(".config"))
        // Ensure system allowlist doesn't interfere
        .env("ORCA_ALLOWLIST_SYSTEM_PATH", "/nonexistent")
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .expect("failed to spawn orca");

    {
        let stdin = child.stdin.as_mut().expect("failed to open stdin");
        serde_json::to_writer(stdin, &input).expect("failed to write json");
    }

    let output = child.wait_with_output().expect("failed to wait for orca");
    String::from_utf8_lossy(&output.stdout).to_string()
}

#[test]
fn test_exact_command_allowlist_works() {
    let cmd = "git reset --hard";
    let allowlist = format!(
        r#"
[[allow]]
exact_command = "{cmd}"
reason = "allowed explicitly"
"#
    );

    let output = run_hook_with_allowlist(cmd, &allowlist);

    assert!(
        !output.contains("deny"),
        "ExactCommand allowlist should allow the command, but got denial: {output}",
    );
    assert!(
        output.is_empty(),
        "Expected empty output for allowed command"
    );
}

// Regression test for orca#132: orca used to block `ee preflight check --cmd
// "<destructive>"` because it substring-matched the destructive verb inside
// the analyzed argument. The argument is consumed as data by `ee`, not
// executed, so the call must be allowed through built-in inspection-wrapper
// exemption — WITHOUT requiring the user to maintain an allowlist entry.
#[test]
fn test_ee_preflight_check_with_destructive_cmd_argument_is_allowed_builtin() {
    // No allowlist content — relying entirely on the built-in exemption.
    let cmd = "ee preflight check --cmd \"git reset --hard HEAD~5\"";
    let output = run_hook_with_allowlist(cmd, "");

    assert!(
        !output.contains("deny"),
        "Built-in inspection-wrapper exemption should allow `ee preflight check --cmd <destructive>`, but got denial: {output}",
    );
    assert!(
        output.is_empty(),
        "Expected empty output for built-in inspection-wrapper exemption, got: {output}",
    );
}

// Regression test for orca#132 anti-bypass: chaining a real destructive
// command after the inspected argument must still block, because at that
// point the destructive verb is no longer purely data.
#[test]
fn test_ee_preflight_check_with_chained_destructive_tail_is_still_blocked() {
    // No allowlist content — verifying default deny semantics still hold for
    // a chained command after the inspection wrapper.
    let cmd = "ee preflight check --cmd \"true\" ; rm -rf /";
    let output = run_hook_with_allowlist(cmd, "");

    assert!(
        output.contains("deny") || output.contains("permissionDecision"),
        "Chained destructive tail must still be blocked even after an inspection wrapper, but got: {output}",
    );
}
