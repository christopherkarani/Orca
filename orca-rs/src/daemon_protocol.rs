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
