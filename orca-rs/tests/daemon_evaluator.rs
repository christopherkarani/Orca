//! Integration test for the daemon evaluator.

mod common;

use std::time::Duration;

fn assert_no_placeholder_text(value: &serde_json::Value) {
    let serialized = serde_json::to_string(value).expect("response value should serialize");
    assert!(
        !serialized.contains("hardcoded placeholder"),
        "daemon response must come from real evaluator, got: {serialized}"
    );
}

#[test]
#[cfg(unix)]
fn daemon_evaluate_commands() {
    let home_dir = tempfile::tempdir().expect("failed to create temp dir");
    let (socket_path, pid_path) = common::socket_and_pid_paths(home_dir.path());

    let child = common::spawn_daemon(home_dir.path());
    common::wait_for_daemon_ready(&socket_path, Duration::from_secs(5));

    let req_deny = r#"{"id":1,"method":"Evaluate","params":{"cwd":"/tmp","command":"rm -rf /"}}"#;
    let response_deny = common::send_request(&socket_path, req_deny);
    let parsed_deny: serde_json::Value =
        serde_json::from_str(&response_deny).expect("response should be valid JSON");

    assert_eq!(
        parsed_deny["id"], 1,
        "id mismatch in response: {}",
        response_deny
    );
    assert_eq!(
        parsed_deny["result"]["status"].as_str(),
        Some("Deny"),
        "expected Deny, got: {response_deny}"
    );
    assert!(
        parsed_deny["result"]["reason"].as_str().is_some(),
        "expected a reason string"
    );
    assert_eq!(
        parsed_deny["result"]["pack_id"].as_str(),
        Some("core.filesystem"),
        "expected real filesystem pack metadata, got: {response_deny}"
    );
    assert_eq!(
        parsed_deny["result"]["pattern_name"].as_str(),
        Some("rm-rf-root-home"),
        "expected real rm-rf-root-home pattern metadata, got: {response_deny}"
    );
    assert_eq!(
        parsed_deny["result"]["severity"].as_str(),
        Some("critical"),
        "expected critical severity from real evaluator, got: {response_deny}"
    );
    assert_no_placeholder_text(&parsed_deny);

    let req_allow =
        r#"{"id":2,"method":"Evaluate","params":{"cwd":"/tmp","command":"git status"}}"#;
    let response_allow = common::send_request(&socket_path, req_allow);
    let parsed_allow: serde_json::Value =
        serde_json::from_str(&response_allow).expect("response should be valid JSON");

    assert_eq!(
        parsed_allow["id"], 2,
        "id mismatch in response: {response_allow}"
    );
    assert_eq!(
        parsed_allow["result"]["status"].as_str(),
        Some("Allow"),
        "expected Allow, got: {response_allow}"
    );
    assert_no_placeholder_text(&parsed_allow);

    let _ = common::send_shutdown(&socket_path);
    common::term_and_wait(child, Duration::from_secs(5));

    assert!(
        !socket_path.exists(),
        "socket should be removed after shutdown"
    );
    assert!(
        !pid_path.exists(),
        "PID file should be removed after shutdown"
    );
}

fn init_git_repo(path: &std::path::Path) {
    std::fs::create_dir_all(path).expect("failed to create repo dir");
    std::process::Command::new("git")
        .args(["init", "-q"])
        .current_dir(path)
        .output()
        .expect("git init should succeed");
}

fn write_project_allowlist(repo_root: &std::path::Path, exact_command: &str) {
    let orca_dir = repo_root.join(".orca");
    std::fs::create_dir_all(&orca_dir).expect("failed to create .orca dir");
    let allowlist = format!(
        r#"
[[allow]]
exact_command = "{exact_command}"
reason = "integration test allowlist"
"#
    );
    std::fs::write(orca_dir.join("allowlist.toml"), allowlist).expect("failed to write allowlist");
}

#[test]
#[cfg(unix)]
fn daemon_evaluate_multi_repo_allowlists() {
    let home_dir = tempfile::tempdir().expect("failed to create temp dir");
    let workspace = home_dir.path().join("workspace");
    std::fs::create_dir_all(&workspace).expect("failed to create workspace");

    let repo_allowed = workspace.join("repo-a");
    let repo_denied = workspace.join("repo-b");
    init_git_repo(&repo_allowed);
    init_git_repo(&repo_denied);

    let cmd = "git reset --hard";
    write_project_allowlist(&repo_allowed, cmd);

    let (socket_path, pid_path) = common::socket_and_pid_paths(home_dir.path());
    let child = common::spawn_daemon(home_dir.path());
    common::wait_for_daemon_ready(&socket_path, Duration::from_secs(5));

    let allowed_cwd = repo_allowed.canonicalize().expect("canonicalize repo-a");
    let denied_cwd = repo_denied.canonicalize().expect("canonicalize repo-b");

    let allow_req = format!(
        r#"{{"id":10,"method":"Evaluate","params":{{"command":"{cmd}","cwd":"{}"}}}}
"#,
        allowed_cwd.display()
    );
    let allow_response = common::send_request(&socket_path, &allow_req);
    let parsed_allow: serde_json::Value =
        serde_json::from_str(&allow_response).expect("allow response should be valid JSON");
    assert_eq!(parsed_allow["id"], 10);
    assert_eq!(
        parsed_allow["result"]["status"].as_str(),
        Some("Allow"),
        "repo-a allowlist should allow command, got: {allow_response}"
    );

    let deny_req = format!(
        r#"{{"id":11,"method":"Evaluate","params":{{"command":"{cmd}","cwd":"{}"}}}}
"#,
        denied_cwd.display()
    );
    let deny_response = common::send_request(&socket_path, &deny_req);
    let parsed_deny: serde_json::Value =
        serde_json::from_str(&deny_response).expect("deny response should be valid JSON");
    assert_eq!(parsed_deny["id"], 11);
    assert_eq!(
        parsed_deny["result"]["status"].as_str(),
        Some("Deny"),
        "repo-b without allowlist should deny command, got: {deny_response}"
    );

    let _ = common::send_shutdown(&socket_path);
    common::term_and_wait(child, Duration::from_secs(5));

    assert!(!socket_path.exists(), "socket should be removed after shutdown");
    assert!(!pid_path.exists(), "PID file should be removed after shutdown");
}



fn write_project_config(repo_root: &std::path::Path, contents: &str) {
    std::fs::write(repo_root.join(".orca.toml"), contents).expect("failed to write .orca.toml");
}

fn write_external_pack(repo_root: &std::path::Path, pack_yaml: &str) {
    let packs_dir = repo_root.join(".orca").join("packs");
    std::fs::create_dir_all(&packs_dir).expect("failed to create packs dir");
    std::fs::write(packs_dir.join("custom.yaml"), pack_yaml).expect("failed to write pack");
}

fn evaluate_at(socket_path: &std::path::Path, id: u64, command: &str, cwd: &std::path::Path) -> serde_json::Value {
    let req = serde_json::json!({
        "id": id,
        "method": "Evaluate",
        "params": {
            "command": command,
            "cwd": cwd.to_string_lossy(),
        }
    });
    let mut payload = serde_json::to_string(&req).expect("request should serialize");
    payload.push('\n');
    let response = common::send_request(socket_path, &payload);
    serde_json::from_str(&response).expect("response should be valid JSON")
}

#[test]
#[cfg(unix)]
fn daemon_warm_reload_picks_up_project_allowlist_change() {
    let home_dir = tempfile::tempdir().expect("failed to create temp dir");
    let repo = home_dir.path().join("repo");
    init_git_repo(&repo);

    let cmd = "git reset --hard";
    let (socket_path, pid_path) = common::socket_and_pid_paths(home_dir.path());
    let child = common::spawn_daemon(home_dir.path());
    common::wait_for_daemon_ready(&socket_path, Duration::from_secs(5));

    let cwd = repo.canonicalize().expect("canonicalize repo");

    let before = evaluate_at(&socket_path, 20, cmd, &cwd);
    assert_eq!(before["result"]["status"].as_str(), Some("Deny"));

    write_project_allowlist(&repo, cmd);

    let after = evaluate_at(&socket_path, 21, cmd, &cwd);
    assert_eq!(
        after["result"]["status"].as_str(),
        Some("Allow"),
        "warm daemon should observe allowlist edit without restart"
    );

    let _ = common::send_shutdown(&socket_path);
    common::term_and_wait(child, Duration::from_secs(5));
    assert!(!socket_path.exists());
    assert!(!pid_path.exists());
}

#[test]
#[cfg(unix)]
fn daemon_warm_reload_picks_up_project_config_change() {
    let home_dir = tempfile::tempdir().expect("failed to create temp dir");
    let repo = home_dir.path().join("repo");
    init_git_repo(&repo);

    let cmd = "echo reload-config-test";
    let block_config = r#"
[[overrides.block]]
pattern = "^echo reload-config-test$"
reason = "blocked for reload test"
"#;

    let (socket_path, pid_path) = common::socket_and_pid_paths(home_dir.path());
    let child = common::spawn_daemon(home_dir.path());
    common::wait_for_daemon_ready(&socket_path, Duration::from_secs(5));

    let cwd = repo.canonicalize().expect("canonicalize repo");

    let before = evaluate_at(&socket_path, 22, cmd, &cwd);
    assert_eq!(before["result"]["status"].as_str(), Some("Allow"));

    write_project_config(&repo, block_config);

    let blocked = evaluate_at(&socket_path, 23, cmd, &cwd);
    assert_eq!(
        blocked["result"]["status"].as_str(),
        Some("Deny"),
        "warm daemon should observe config block override without restart"
    );

    std::fs::remove_file(repo.join(".orca.toml")).expect("remove config");

    let after_delete = evaluate_at(&socket_path, 24, cmd, &cwd);
    assert_eq!(
        after_delete["result"]["status"].as_str(),
        Some("Allow"),
        "warm daemon should observe deleted project config without restart"
    );

    let _ = common::send_shutdown(&socket_path);
    common::term_and_wait(child, Duration::from_secs(5));
    assert!(!socket_path.exists());
    assert!(!pid_path.exists());
}

#[test]
#[cfg(unix)]
fn daemon_invalid_project_config_returns_error_not_stale_state() {
    let home_dir = tempfile::tempdir().expect("failed to create temp dir");
    let repo = home_dir.path().join("repo");
    init_git_repo(&repo);

    let cmd = "echo invalid-config-test";
    let allow_config = r#"
[[overrides.allow]]
pattern = "^echo invalid-config-test$"
reason = "allowed via config"
"#;
    write_project_config(&repo, allow_config);

    let (socket_path, pid_path) = common::socket_and_pid_paths(home_dir.path());
    let child = common::spawn_daemon(home_dir.path());
    common::wait_for_daemon_ready(&socket_path, Duration::from_secs(5));

    let cwd = repo.canonicalize().expect("canonicalize repo");

    let allowed = evaluate_at(&socket_path, 25, cmd, &cwd);
    assert_eq!(allowed["result"]["status"].as_str(), Some("Allow"));

    write_project_config(&repo, "[[overrides.block]]
invalid_syntax = 
");

    let invalid = evaluate_at(&socket_path, 26, cmd, &cwd);
    assert_eq!(invalid["result"]["status"].as_str(), Some("Error"));
    assert!(
        invalid["result"]["message"]
            .as_str()
            .unwrap()
            .contains("invalid project config"),
        "expected structured config error, got: {invalid}"
    );

    write_project_config(&repo, allow_config);

    let fixed = evaluate_at(&socket_path, 27, cmd, &cwd);
    assert_eq!(
        fixed["result"]["status"].as_str(),
        Some("Allow"),
        "fixed project config should be picked up on next request"
    );

    let _ = common::send_shutdown(&socket_path);
    common::term_and_wait(child, Duration::from_secs(5));
    assert!(!socket_path.exists());
    assert!(!pid_path.exists());
}

#[test]
#[cfg(unix)]
fn daemon_invalid_project_allowlist_returns_error_not_stale_allow() {
    let home_dir = tempfile::tempdir().expect("failed to create temp dir");
    let repo = home_dir.path().join("repo");
    init_git_repo(&repo);

    let cmd = "git reset --hard";
    write_project_allowlist(&repo, cmd);

    let (socket_path, pid_path) = common::socket_and_pid_paths(home_dir.path());
    let child = common::spawn_daemon(home_dir.path());
    common::wait_for_daemon_ready(&socket_path, Duration::from_secs(5));

    let cwd = repo.canonicalize().expect("canonicalize repo");

    let allowed = evaluate_at(&socket_path, 28, cmd, &cwd);
    assert_eq!(allowed["result"]["status"].as_str(), Some("Allow"));

    let orca_dir = repo.join(".orca");
    std::fs::write(
        orca_dir.join("allowlist.toml"),
        "[[allow]]
invalid_syntax = 
",
    )
    .expect("write invalid allowlist");

    let invalid = evaluate_at(&socket_path, 29, cmd, &cwd);
    assert_eq!(invalid["result"]["status"].as_str(), Some("Error"));
    assert!(
        invalid["result"]["message"]
            .as_str()
            .unwrap()
            .contains("invalid project allowlist"),
        "expected structured allowlist error, got: {invalid}"
    );

    write_project_allowlist(&repo, cmd);

    let fixed = evaluate_at(&socket_path, 30, cmd, &cwd);
    assert_eq!(
        fixed["result"]["status"].as_str(),
        Some("Allow"),
        "fixed allowlist should be picked up on next request"
    );

    let _ = common::send_shutdown(&socket_path);
    common::term_and_wait(child, Duration::from_secs(5));
    assert!(!socket_path.exists());
    assert!(!pid_path.exists());
}

#[test]
#[cfg(unix)]
fn daemon_warm_reload_picks_up_external_pack_change() {
    let home_dir = tempfile::tempdir().expect("failed to create temp dir");
    let repo = home_dir.path().join("repo");
    init_git_repo(&repo);

    let config = r#"
[packs]
custom_paths = [".orca/packs/custom.yaml"]
"#;
    write_project_config(&repo, config);

    let pack_v1 = r#"
schema_version: 1
id: custom.reload
name: Reload Pack
version: 1.0.0
keywords: [reloadpack]
destructive_patterns:
  - name: block-reload-cmd
    pattern: reloadpack-danger
    severity: high
    description: blocked by external pack
"#;
    write_external_pack(&repo, pack_v1);

    let cmd = "reloadpack-danger";
    let (socket_path, pid_path) = common::socket_and_pid_paths(home_dir.path());
    let child = common::spawn_daemon(home_dir.path());
    common::wait_for_daemon_ready(&socket_path, Duration::from_secs(5));

    let cwd = repo.canonicalize().expect("canonicalize repo");

    let denied = evaluate_at(&socket_path, 31, cmd, &cwd);
    assert_eq!(
        denied["result"]["status"].as_str(),
        Some("Deny"),
        "external pack should deny command, got: {denied}"
    );

    let pack_v2 = r#"
schema_version: 1
id: custom.reload
name: Reload Pack
version: 1.0.0
keywords: [reloadpack]
destructive_patterns: []
"#;
    write_external_pack(&repo, pack_v2);

    let allowed = evaluate_at(&socket_path, 32, cmd, &cwd);
    assert_eq!(
        allowed["result"]["status"].as_str(),
        Some("Allow"),
        "warm daemon should observe external pack edit without restart, got: {allowed}"
    );

    let _ = common::send_shutdown(&socket_path);
    common::term_and_wait(child, Duration::from_secs(5));
    assert!(!socket_path.exists());
    assert!(!pid_path.exists());
}
