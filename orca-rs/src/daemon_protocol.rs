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

/// Result payload for a daemon response.
#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "status")]
pub enum ResultPayload {
    Pong,
    Allow { reason: String },
    Deny { reason: String },
    Error { message: String },
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
}
