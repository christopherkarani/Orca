use serde::{Deserialize, Serialize};

/// Request envelope sent by the Zig CLI over the Unix Domain Socket.
///
/// Each line on the wire is a JSON object whose `method` field selects
/// the variant.  The `params` field is flattened into the variant
/// payload via `#[serde(tag = "method", content = "params")]`.
#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "method", content = "params")]
pub enum DaemonRequest {
    Ping,
    Evaluate {
        command: String,
        cwd: Option<String>,
    },
    /// Execute a supported Rust CLI operation without terminating the daemon.
    ExecuteCli {
        argv: Vec<String>,
    },
    Shutdown,
}

/// Client request envelope carrying a correlation `id` and the typed
/// request body.
///
/// The Zig client sends objects like `{"id": 1, "method": "Ping"}`.
/// Serde flattens the `method`/`params` fields into `DaemonRequest`.
#[derive(Debug, Serialize, Deserialize)]
pub struct ClientEnvelope {
    pub id: u64,
    #[serde(flatten)]
    pub body: DaemonRequest,
}

/// Response envelope returned by the daemon for every `DaemonRequest`.
///
/// Responses are line-delimited JSON.  The `id` field echoes the request
/// id provided by the client so callers can correlate out-of-order
/// replies if they ever move to pipelining.
#[derive(Debug, Serialize, Deserialize)]
pub struct DaemonResponse {
    pub id: u64,
    pub result: ResultPayload,
}

/// Suggestion alternative for a destructive pattern.
#[derive(Debug, Serialize, Deserialize)]
pub struct SuggestionPayload {
    pub command: String,
    pub description: String,
    pub platform: String,
}

/// Allowlist override information.
#[derive(Debug, Serialize, Deserialize)]
pub struct AllowlistOverridePayload {
    pub layer: String,
    pub reason: String,
}

/// Result payload for a daemon response.
#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "status")]
pub enum ResultPayload {
    Pong,
    Allow {
        reason: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        allowlist_override: Option<AllowlistOverridePayload>,
        #[serde(skip_serializing_if = "Option::is_none")]
        graduated_response: Option<serde_json::Value>,
        #[serde(skip_serializing_if = "Option::is_none")]
        session_occurrence: Option<u32>,
    },
    Deny {
        reason: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        pack_id: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        pattern_name: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        severity: Option<crate::packs::Severity>,
        #[serde(skip_serializing_if = "Option::is_none")]
        matched_text_preview: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        explanation: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        suggestions: Option<Vec<SuggestionPayload>>,
        #[serde(skip_serializing_if = "Option::is_none")]
        graduated_response: Option<serde_json::Value>,
        #[serde(skip_serializing_if = "Option::is_none")]
        session_occurrence: Option<u32>,
    },
    Error {
        message: String,
    },
    /// Result from a daemon-side CLI invocation (`ExecuteCli` request).
    CliExecution {
        stdout: String,
        #[serde(skip_serializing_if = "String::is_empty")]
        stderr: String,
        exit_code: i32,
    },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deserializes_ping_with_null_params() {
        let envelope: ClientEnvelope =
            serde_json::from_str(r#"{"id":1,"method":"Ping","params":null}"#).unwrap();
        assert_eq!(envelope.id, 1);
        assert!(matches!(envelope.body, DaemonRequest::Ping));
    }

    #[test]
    fn deserializes_shutdown_with_null_params() {
        let envelope: ClientEnvelope =
            serde_json::from_str(r#"{"id":2,"method":"Shutdown","params":null}"#).unwrap();
        assert_eq!(envelope.id, 2);
        assert!(matches!(envelope.body, DaemonRequest::Shutdown));
    }

    #[test]
    fn allow_payload_omits_absent_optional_metadata() {
        let response = DaemonResponse {
            id: 7,
            result: ResultPayload::Allow {
                reason: "Command allowed by evaluator".to_string(),
                allowlist_override: None,
                graduated_response: None,
                session_occurrence: None,
            },
        };

        let value = serde_json::to_value(response).unwrap();
        let result = value.get("result").unwrap();
        assert_eq!(
            result.get("status").and_then(serde_json::Value::as_str),
            Some("Allow")
        );
        assert!(result.get("allowlist_override").is_none());
        assert!(result.get("graduated_response").is_none());
        assert!(result.get("session_occurrence").is_none());
    }

    #[test]
    fn deserializes_execute_cli_with_argv() {
        let envelope: ClientEnvelope = serde_json::from_str(
            r#"{"id":3,"method":"ExecuteCli","params":{"argv":["version"]}}"#,
        )
        .unwrap();
        assert_eq!(envelope.id, 3);
        match envelope.body {
            DaemonRequest::ExecuteCli { argv } => {
                assert_eq!(argv, vec!["version".to_string()]);
            }
            other => panic!("expected ExecuteCli, got {other:?}"),
        }
    }

    #[test]
    fn serializes_cli_execution_response() {
        let response = DaemonResponse {
            id: 9,
            result: ResultPayload::CliExecution {
                stdout: "0.6.0\n".to_string(),
                stderr: String::new(),
                exit_code: 0,
            },
        };

        let value = serde_json::to_value(response).unwrap();
        assert_eq!(value["id"], 9);
        let result = value.get("result").unwrap();
        assert_eq!(
            result.get("status").and_then(serde_json::Value::as_str),
            Some("CliExecution")
        );
        assert_eq!(
            result.get("stdout").and_then(serde_json::Value::as_str),
            Some("0.6.0\n")
        );
        assert!(result.get("stderr").is_none());
        assert_eq!(result.get("exit_code").and_then(serde_json::Value::as_i64), Some(0));
    }

    #[test]
    fn cli_execution_includes_stderr_when_present() {
        let response = DaemonResponse {
            id: 10,
            result: ResultPayload::CliExecution {
                stdout: String::new(),
                stderr: "unsupported daemon CLI command: scan".to_string(),
                exit_code: 4,
            },
        };

        let value = serde_json::to_value(response).unwrap();
        let result = value.get("result").unwrap();
        assert_eq!(
            result.get("stderr").and_then(serde_json::Value::as_str),
            Some("unsupported daemon CLI command: scan")
        );
    }

    #[test]
    fn deny_payload_omits_absent_optional_metadata() {
        let response = DaemonResponse {
            id: 8,
            result: ResultPayload::Deny {
                reason: "Command denied by evaluator".to_string(),
                pack_id: None,
                pattern_name: None,
                severity: None,
                matched_text_preview: None,
                explanation: None,
                suggestions: None,
                graduated_response: None,
                session_occurrence: None,
            },
        };

        let value = serde_json::to_value(response).unwrap();
        let result = value.get("result").unwrap();
        assert_eq!(
            result.get("status").and_then(serde_json::Value::as_str),
            Some("Deny")
        );
        assert!(result.get("pack_id").is_none());
        assert!(result.get("pattern_name").is_none());
        assert!(result.get("severity").is_none());
        assert!(result.get("matched_text_preview").is_none());
        assert!(result.get("explanation").is_none());
        assert!(result.get("suggestions").is_none());
        assert!(result.get("graduated_response").is_none());
        assert!(result.get("session_occurrence").is_none());
    }
}
