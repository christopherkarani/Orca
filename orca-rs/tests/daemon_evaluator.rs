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
