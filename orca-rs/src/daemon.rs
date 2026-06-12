#![cfg_attr(not(test), allow(unsafe_code))]

use std::path::{Path, PathBuf};
use std::process;

/// Check whether a process with the given PID is currently alive.
///
/// Uses `libc::kill(pid, 0)` which returns success iff the process exists
/// and the caller has permission to signal it.  EPERM means the process
/// is alive (we just lack permission to signal it); ESRCH means it is
/// dead.  EINVAL means the PID was invalid.  Any other error is treated
/// conservatively as alive (fail-closed) so that a live daemon's socket
/// is never stolen.
fn is_process_alive(pid: u32) -> bool {
    if pid == 0 {
        return false;
    }
    let pid_t: libc::pid_t = match i32::try_from(pid) {
        Ok(p) => p,
        Err(_) => return false,
    };
    let result = unsafe { libc::kill(pid_t, 0) };
    if result == 0 {
        return true;
    }
    match std::io::Error::last_os_error().raw_os_error().unwrap_or(0) {
        libc::ESRCH => false,
        libc::EPERM => true,
        libc::EINVAL => false,
        _ => true,
    }
}

use crate::allowlist::{LayeredAllowlist, load_default_allowlists};
use crate::config::{CompiledOverrides, Config, HeredocSettings};
use crate::daemon_protocol::{
    AllowlistOverridePayload, ClientEnvelope, DaemonRequest, DaemonResponse, ResultPayload,
    SuggestionPayload,
};
use crate::evaluator::{
    EvaluationDecision, EvaluationResult, PatternMatch,
    evaluate_command_with_pack_order_deadline_at_path,
};
use crate::packs::{REGISTRY, load_external_packs};
use crate::perf::Deadline;
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::watch;

const DAEMON_EVALUATION_DEADLINE: Duration = Duration::from_millis(100);

struct AppState {
    allowlists: LayeredAllowlist,
    compiled_overrides: CompiledOverrides,
    heredoc_settings: HeredocSettings,
    ordered_packs: Vec<String>,
    enabled_keywords: Vec<&'static str>,
    keyword_index: Option<crate::packs::EnabledKeywordIndex>,
}

impl AppState {
    fn load() -> Self {
        // TODO(phase1a): Config::load() is CWD-dependent. Daemon mode loads
        // it once at startup; per-request CWD-aware reloads are out of scope.
        let config = Config::load();
        let allowlists = load_default_allowlists();
        let compiled_overrides = config.overrides.compile();
        let heredoc_settings = config.heredoc_settings();

        let external_paths = config.packs.expand_custom_paths();
        let external_store = load_external_packs(&external_paths);

        let mut enabled_pack_ids = config.enabled_pack_ids();
        let mut ordered_packs = REGISTRY.expand_enabled_ordered(&enabled_pack_ids);
        let mut has_external_packs = false;
        for id in external_store.pack_ids() {
            has_external_packs = true;
            if !ordered_packs.contains(id) {
                ordered_packs.push(id.clone());
            }
            enabled_pack_ids.insert(id.clone());
        }

        let mut enabled_keywords = REGISTRY.collect_enabled_keywords(&enabled_pack_ids);
        enabled_keywords.extend(external_store.keywords().iter().copied());

        // TODO(phase1a): External packs are not represented in the keyword
        // index yet, so disable the fast-path index when any are configured.
        let keyword_index = if has_external_packs {
            None
        } else {
            REGISTRY.build_enabled_keyword_index(&ordered_packs)
        };

        Self {
            allowlists,
            compiled_overrides,
            heredoc_settings,
            ordered_packs,
            enabled_keywords,
            keyword_index,
        }
    }

    fn evaluate(&self, command: &str) -> EvaluationResult {
        let deadline = Deadline::new(DAEMON_EVALUATION_DEADLINE);
        evaluate_command_with_pack_order_deadline_at_path(
            command,
            &self.enabled_keywords,
            &self.ordered_packs,
            self.keyword_index.as_ref(),
            &self.compiled_overrides,
            &self.allowlists,
            &self.heredoc_settings,
            None,
            // TODO(phase1a): The Zig client sends cwd, but Phase 1A keeps
            // daemon evaluation bound to startup state and ignores request cwd.
            None,
            Some(&deadline),
        )
    }
}

/// Run the NDJSON-over-UDS daemon until `shutdown` signals `true`.
///
/// On success the socket and PID file are created; on shutdown they are
/// removed before returning.  All request handling is synchronous per
/// connection (one response per line) and never calls `process::exit`.
///
/// # Errors
///
/// Returns an error if the socket cannot be bound or the PID file cannot
/// be written.  Individual request parse errors are encoded as
/// `DaemonResponse::Error` and do not stop the daemon.
pub async fn run_daemon(
    socket_path: &Path,
    pid_path: &Path,
    mut shutdown: watch::Receiver<bool>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    // Ensure parent directory exists.
    if let Some(parent) = socket_path.parent() {
        tokio::fs::create_dir_all(parent).await?;
    }

    let app_state = Arc::new(AppState::load());

    // If a socket file already exists, decide whether it is stale before
    // we write our own PID file.  This preserves the live daemon's PID
    // file when we fail with "socket in use".
    if socket_path.exists() {
        let is_stale = match tokio::fs::read_to_string(pid_path).await {
            Ok(content) => match content.trim().parse::<u32>() {
                Ok(pid) => !is_process_alive(pid),
                Err(_) => true, // invalid PID → treat as stale
            },
            Err(_) => true, // missing/unreadable PID file → best effort
        };

        if is_stale {
            tracing::warn!(
                path = %socket_path.display(),
                "removing stale socket from previous daemon"
            );
            if let Err(e) = tokio::fs::remove_file(socket_path).await {
                // Ignore "not found" — it may have raced away.
                if e.kind() != std::io::ErrorKind::NotFound {
                    return Err(Box::new(e));
                }
            }
        } else {
            return Err(format!(
                "socket {} is in use by a live daemon (pid file: {})",
                socket_path.display(),
                pid_path.display()
            )
            .into());
        }
    }

    // Write PID file early so external observers know a daemon is
    // starting, then bind the socket.  If binding fails we must remove
    // the PID file so we don't leave a stale claim behind.
    tokio::fs::write(pid_path, process::id().to_string()).await?;

    let listener = match UnixListener::bind(socket_path) {
        Ok(l) => l,
        Err(e) if e.kind() == std::io::ErrorKind::AddrInUse => {
            // Someone else bound between our existence check and bind.
            tracing::warn!(
                path = %socket_path.display(),
                "socket contention detected; cleaning up PID file"
            );
            if let Err(cleanup_err) = tokio::fs::remove_file(pid_path).await {
                tracing::warn!(
                    path = %pid_path.display(),
                    error = %cleanup_err,
                    "failed to remove PID file after bind collision"
                );
            }
            return Err(format!(
                "socket {} is already bound by another daemon",
                socket_path.display()
            )
            .into());
        }
        Err(e) => {
            if let Err(cleanup_err) = tokio::fs::remove_file(pid_path).await {
                tracing::warn!(
                    path = %pid_path.display(),
                    error = %cleanup_err,
                    "failed to remove PID file after failed bind"
                );
            }
            return Err(Box::new(e));
        }
    };
    tracing::info!(path = %socket_path.display(), "orca-daemon bound UDS socket");

    let socket_path_buf: PathBuf = socket_path.to_path_buf();
    let pid_path_buf: PathBuf = pid_path.to_path_buf();

    #[cfg(unix)]
    let mut sigterm = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
        .expect("failed to install SIGTERM handler");

    #[cfg(unix)]
    loop {
        tokio::select! {
            accept_result = listener.accept() => {
                match accept_result {
                    Ok((stream, _addr)) => {
                        let state = Arc::clone(&app_state);
                        tokio::spawn(handle_connection(stream, state));
                    }
                    Err(e) => {
                        tracing::warn!(error = %e, "UDS accept failed");
                    }
                }
            }
            _ = shutdown.changed() => {
                if *shutdown.borrow() {
                    break;
                }
            }
            _ = sigterm.recv() => {
                tracing::info!("received SIGTERM, starting graceful shutdown");
                break;
            }
        }
    }

    #[cfg(not(unix))]
    loop {
        tokio::select! {
            accept_result = listener.accept() => {
                match accept_result {
                    Ok((stream, _addr)) => {
                        let state = Arc::clone(&app_state);
                        tokio::spawn(handle_connection(stream, state));
                    }
                    Err(e) => {
                        tracing::warn!(error = %e, "UDS accept failed");
                    }
                }
            }
            _ = shutdown.changed() => {
                if *shutdown.borrow() {
                    break;
                }
            }
        }
    }

    // Clean up runtime artifacts.
    if let Err(e) = tokio::fs::remove_file(&socket_path_buf).await {
        tracing::warn!(path = %socket_path_buf.display(), error = %e, "failed to remove socket");
    }
    if let Err(e) = tokio::fs::remove_file(&pid_path_buf).await {
        tracing::warn!(path = %pid_path_buf.display(), error = %e, "failed to remove pid file");
    }

    tracing::info!("orca-daemon shut down gracefully");
    Ok(())
}

async fn handle_connection(stream: UnixStream, state: Arc<AppState>) {
    let (read_half, mut write_half) = stream.into_split();
    let reader = BufReader::new(read_half);
    let mut lines = reader.lines();

    while let Ok(Some(line)) = lines.next_line().await {
        let envelope: ClientEnvelope = match serde_json::from_str(&line) {
            Ok(req) => req,
            Err(e) => {
                let response = DaemonResponse {
                    id: 0,
                    result: ResultPayload::Error {
                        message: format!("parse error: {e}"),
                    },
                };
                if let Err(e) = write_response(&mut write_half, &response).await {
                    tracing::warn!(error = %e, "failed to write error response");
                    break;
                }
                continue;
            }
        };

        let id = envelope.id;
        let is_shutdown = matches!(envelope.body, DaemonRequest::Shutdown);
        let response = match envelope.body {
            DaemonRequest::Ping => DaemonResponse {
                id,
                result: ResultPayload::Pong,
            },
            DaemonRequest::Evaluate { command, cwd: _cwd } => {
                let eval_result = state.evaluate(&command);
                DaemonResponse {
                    id,
                    result: result_payload_from_evaluation(eval_result),
                }
            }
            DaemonRequest::Shutdown => DaemonResponse {
                id,
                result: ResultPayload::Pong,
            },
        };

        if let Err(e) = write_response(&mut write_half, &response).await {
            tracing::warn!(error = %e, "failed to write response");
            break;
        }

        // Shutdown request is acknowledged on this connection before the
        // daemon loop exits via the shutdown channel.  We intentionally do
        // NOT call process::exit here.
        if is_shutdown {
            // Signal the main loop to shut down gracefully.
            // The shutdown watch is owned by the main loop; we cannot send
            // through it directly, but the Zig client is expected to send
            // SIGTERM after the Shutdown response.  For now, close this
            // connection and let the daemon's signal handler do the rest.
            break;
        }
    }
}

async fn write_response(
    write_half: &mut tokio::net::unix::OwnedWriteHalf,
    response: &DaemonResponse,
) -> tokio::io::Result<()> {
    let mut json = serde_json::to_vec(response)?;
    json.push(b'\n');
    write_half.write_all(&json).await?;
    write_half.flush().await
}

fn result_payload_from_evaluation(result: EvaluationResult) -> ResultPayload {
    if result.skipped_due_to_budget {
        return ResultPayload::Deny {
            reason: "Command denied: evaluator budget exceeded".to_string(),
            pack_id: None,
            pattern_name: None,
            severity: None,
            matched_text_preview: None,
            explanation: None,
            suggestions: None,
            graduated_response: None,
            session_occurrence: None,
        };
    }

    match result.decision {
        EvaluationDecision::Allow => ResultPayload::Allow {
            reason: "Command allowed by evaluator".to_string(),
            allowlist_override: result.allowlist_override.map(|override_info| {
                AllowlistOverridePayload {
                    layer: override_info.layer.label().to_string(),
                    reason: override_info.reason,
                }
            }),
            // TODO(phase1a): The response schema is ready, but session
            // tracking/graduated responses are out of scope for this phase.
            graduated_response: None,
            session_occurrence: None,
        },
        EvaluationDecision::Deny => deny_payload(result.pattern_info),
    }
}

fn deny_payload(pattern_info: Option<PatternMatch>) -> ResultPayload {
    let Some(info) = pattern_info else {
        return ResultPayload::Deny {
            reason: "Command denied by evaluator".to_string(),
            pack_id: None,
            pattern_name: None,
            severity: None,
            matched_text_preview: None,
            explanation: None,
            suggestions: None,
            graduated_response: None,
            session_occurrence: None,
        };
    };

    let suggestions: Vec<SuggestionPayload> = info
        .suggestions
        .iter()
        .map(|suggestion| SuggestionPayload {
            command: suggestion.command.to_string(),
            description: suggestion.description.to_string(),
            platform: suggestion.platform.label().to_string(),
        })
        .collect();

    ResultPayload::Deny {
        reason: info.reason,
        pack_id: info.pack_id,
        pattern_name: info.pattern_name,
        severity: info.severity,
        matched_text_preview: info.matched_text_preview,
        explanation: info.explanation,
        suggestions: (!suggestions.is_empty()).then_some(suggestions),
        // TODO(phase1a): The response schema is ready, but session
        // tracking/graduated responses are out of scope for this phase.
        graduated_response: None,
        session_occurrence: None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn evaluator_budget_skip_denies_in_daemon_mode() {
        let result = EvaluationResult::allowed_due_to_budget();

        let payload = result_payload_from_evaluation(result);

        match payload {
            ResultPayload::Deny {
                reason,
                pack_id,
                pattern_name,
                ..
            } => {
                assert_eq!(reason, "Command denied: evaluator budget exceeded");
                assert!(pack_id.is_none());
                assert!(pattern_name.is_none());
            }
            other => panic!("expected daemon budget skip to deny, got {other:?}"),
        }
    }
}
