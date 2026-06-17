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

use crate::allowlist::{AllowlistLayer, LayeredAllowlist, load_allowlists_from};
use crate::branding::{CONFIG_DIR, PROJECT_CONFIG_FILE, PROJECT_DATA_DIR};
use crate::config::{
    self, CompiledOverrides, Config, HeredocSettings, REPO_ROOT_SEARCH_MAX_HOPS,
};
use crate::daemon_cli::execute_cli;
use crate::daemon_protocol::{
    AllowlistOverridePayload, ClientEnvelope, DaemonRequest, DaemonResponse, ResultPayload,
    SuggestionPayload,
};
use crate::evaluator::{
    EvaluationDecision, EvaluationResult, PatternMatch,
    evaluate_command_with_pack_order_deadline_at_path,
};
use crate::packs::{ExternalPackStore, REGISTRY};
use crate::perf::Deadline;
use std::collections::HashMap;
use std::sync::{Arc, LazyLock, Mutex};
use std::time::Duration;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::watch;

const DAEMON_EVALUATION_DEADLINE: Duration = Duration::from_millis(100);

/// File metadata and env snapshot for deterministic cwd-scoped cache invalidation.
#[derive(Clone, PartialEq, Eq)]
struct ReloadFingerprint {
    files: Vec<(PathBuf, u64, u128)>,
    env: Vec<(String, String)>,
}

struct EvaluationContextCache {
    entries: HashMap<PathBuf, (ReloadFingerprint, Arc<EvaluationContext>)>,
}

static EVAL_CONTEXT_CACHE: LazyLock<Mutex<EvaluationContextCache>> = LazyLock::new(|| {
    Mutex::new(EvaluationContextCache {
        entries: HashMap::new(),
    })
});

struct EvaluationContext {
    allowlists: LayeredAllowlist,
    compiled_overrides: CompiledOverrides,
    heredoc_settings: HeredocSettings,
    ordered_packs: Vec<String>,
    enabled_keywords: Vec<&'static str>,
    keyword_index: Option<crate::packs::EnabledKeywordIndex>,
    external_store: ExternalPackStore,
}

impl EvaluationContext {
    fn build_at(cwd: &Path, config: &Config) -> Result<Self, String> {
        let allowlists = load_allowlists_from(Some(cwd));
        if let Some(err) = project_allowlist_load_error(&allowlists) {
            return Err(err);
        }

        let compiled_overrides = config.overrides.compile();
        let heredoc_settings = config.heredoc_settings();

        let external_paths = config.packs.expand_custom_paths_from(Some(cwd));
        let external_store = ExternalPackStore::load_from_paths_owned(&external_paths);

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

        // External packs are not represented in the keyword index yet, so
        // disable the fast-path index when any are configured.
        let keyword_index = if has_external_packs {
            None
        } else {
            REGISTRY.build_enabled_keyword_index(&ordered_packs)
        };

        Ok(Self {
            allowlists,
            compiled_overrides,
            heredoc_settings,
            ordered_packs,
            enabled_keywords,
            keyword_index,
            external_store,
        })
    }

    fn evaluate(&self, command: &str, cwd: &Path) -> EvaluationResult {
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
            Some(cwd),
            Some(&self.external_store),
            Some(&deadline),
        )
    }
}

fn project_allowlist_load_error(allowlists: &LayeredAllowlist) -> Option<String> {
    for layer in &allowlists.layers {
        if layer.layer != AllowlistLayer::Project {
            continue;
        }
        let Some(first) = layer.file.errors.first() else {
            continue;
        };
        return Some(format!(
            "invalid project allowlist '{}': {}",
            layer.path.display(),
            first.message
        ));
    }
    None
}

fn file_stat(path: &Path) -> Option<(u64, u128)> {
    let meta = std::fs::metadata(path).ok()?;
    let modified = meta.modified().ok()?;
    let mtime = modified
        .duration_since(std::time::UNIX_EPOCH)
        .ok()?
        .as_nanos();
    Some((meta.len(), mtime))
}

fn collect_reload_paths(cwd: &Path, config: &Config) -> Vec<PathBuf> {
    let mut paths = Vec::new();

    if let Some(repo_root) = config::find_repo_root(cwd, REPO_ROOT_SEARCH_MAX_HOPS) {
        paths.push(repo_root.join(PROJECT_CONFIG_FILE));
        paths.push(repo_root.join(PROJECT_DATA_DIR).join("allowlist.toml"));
    }

    if let Ok(xdg_home) = std::env::var("XDG_CONFIG_HOME") {
        if !xdg_home.trim().is_empty() {
            paths.push(
                PathBuf::from(xdg_home.trim())
                    .join(CONFIG_DIR)
                    .join("config.toml"),
            );
            paths.push(
                PathBuf::from(xdg_home.trim())
                    .join(CONFIG_DIR)
                    .join("allowlist.toml"),
            );
        }
    }

    if let Some(home) = dirs::home_dir() {
        paths.push(
            home.join(".config")
                .join(CONFIG_DIR)
                .join("config.toml"),
        );
        paths.push(
            home.join(".config")
                .join(CONFIG_DIR)
                .join("allowlist.toml"),
        );
    }

    if let Some(config_dir) = dirs::config_dir() {
        paths.push(config_dir.join(CONFIG_DIR).join("config.toml"));
        paths.push(config_dir.join(CONFIG_DIR).join("allowlist.toml"));
    }

    paths.push(PathBuf::from("/etc").join(CONFIG_DIR).join("config.toml"));

    let system_allowlist = std::env::var(format!("{}_ALLOWLIST_SYSTEM_PATH", crate::branding::ENV_PREFIX))
        .map(|path| {
            let trimmed = path.trim();
            if trimmed.is_empty() {
                None
            } else {
                Some(PathBuf::from(trimmed))
            }
        })
        .unwrap_or_else(|_| Some(PathBuf::from(format!("/etc/{CONFIG_DIR}/allowlist.toml"))));
    if let Some(path) = system_allowlist {
        paths.push(path);
    }

    if let Ok(explicit) = std::env::var(crate::config::ENV_CONFIG_PATH) {
        if let Some(path) = config::resolve_config_path_value(&explicit, Some(cwd)) {
            paths.push(path);
        }
    }

    for path in config.packs.expand_custom_paths_from(Some(cwd)) {
        paths.push(PathBuf::from(path));
    }

    paths.sort();
    paths.dedup();
    paths
}

fn collect_reload_fingerprint(cwd: &Path, config: &Config) -> ReloadFingerprint {
    let mut entries = Vec::new();
    for path in collect_reload_paths(cwd, config) {
        let (size, mtime) = file_stat(&path).unwrap_or((0, 0));
        entries.push((path, size, mtime));
    }
    ReloadFingerprint {
        files: entries,
        env: Config::daemon_reload_env_snapshot(),
    }
}

fn evaluation_context_for_cwd(cwd: &Path) -> Result<Arc<EvaluationContext>, String> {
    if let Some(err) = Config::project_config_load_error(cwd) {
        return Err(err);
    }

    let config = Config::load_from(Some(cwd));
    let fingerprint = collect_reload_fingerprint(cwd, &config);
    let canonical = cwd.to_path_buf();

    {
        let cache = EVAL_CONTEXT_CACHE
            .lock()
            .map_err(|_| "evaluation cache lock poisoned".to_string())?;
        if let Some((cached_fp, ctx)) = cache.entries.get(&canonical) {
            if cached_fp == &fingerprint {
                return Ok(Arc::clone(ctx));
            }
        }
    }

    let ctx = Arc::new(EvaluationContext::build_at(cwd, &config)?);
    let mut cache = EVAL_CONTEXT_CACHE
        .lock()
        .map_err(|_| "evaluation cache lock poisoned".to_string())?;
    cache
        .entries
        .insert(canonical, (fingerprint, Arc::clone(&ctx)));
    Ok(ctx)
}

/// Resolve the evaluation working directory from a daemon request.
///
/// The client must send an absolute path. Relative values are rejected because
/// they would resolve against the daemon process working directory, not the
/// hook/run client workspace.
///
/// Returns an error when `cwd` is missing, relative, does not exist, or is not a directory.
fn resolve_evaluation_cwd(request_cwd: Option<&str>) -> Result<PathBuf, String> {
    let Some(cwd_str) = request_cwd else {
        return Err("missing cwd in Evaluate request".to_string());
    };

    if cwd_str.trim().is_empty() {
        return Err("missing cwd in Evaluate request".to_string());
    }

    let path = PathBuf::from(cwd_str);
    if !path.is_absolute() {
        return Err(format!("invalid cwd: path must be absolute: {cwd_str}"));
    }
    if !path.exists() {
        return Err(format!("invalid cwd: path does not exist: {cwd_str}"));
    }
    if !path.is_dir() {
        return Err(format!("invalid cwd: not a directory: {cwd_str}"));
    }

    path.canonicalize()
        .map_err(|e| format!("invalid cwd: cannot canonicalize {cwd_str}: {e}"))
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
    shutdown_tx: watch::Sender<bool>,
    mut shutdown_rx: watch::Receiver<bool>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    // Ensure parent directory exists.
    if let Some(parent) = socket_path.parent() {
        tokio::fs::create_dir_all(parent).await?;
    }

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
    let shutdown_tx = Arc::new(shutdown_tx);

    #[cfg(unix)]
    let mut sigterm = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
        .expect("failed to install SIGTERM handler");

    #[cfg(unix)]
    loop {
        tokio::select! {
            accept_result = listener.accept() => {
                match accept_result {
                    Ok((stream, _addr)) => {
                        tokio::spawn(handle_connection(stream, Arc::clone(&shutdown_tx)));
                    }
                    Err(e) => {
                        tracing::warn!(error = %e, "UDS accept failed");
                    }
                }
            }
            _ = shutdown_rx.changed() => {
                if *shutdown_rx.borrow() {
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
                        tokio::spawn(handle_connection(stream, Arc::clone(&shutdown_tx)));
                    }
                    Err(e) => {
                        tracing::warn!(error = %e, "UDS accept failed");
                    }
                }
            }
            _ = shutdown_rx.changed() => {
                if *shutdown_rx.borrow() {
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

async fn handle_connection(stream: UnixStream, shutdown_tx: Arc<watch::Sender<bool>>) {
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
            DaemonRequest::Evaluate { command, cwd } => {
                match resolve_evaluation_cwd(cwd.as_deref()) {
                    Ok(eval_cwd) => match evaluation_context_for_cwd(&eval_cwd) {
                        Ok(ctx) => {
                            let eval_result = ctx.evaluate(&command, &eval_cwd);
                            DaemonResponse {
                                id,
                                result: result_payload_from_evaluation(eval_result),
                            }
                        }
                        Err(message) => DaemonResponse {
                            id,
                            result: ResultPayload::Error { message },
                        },
                    },
                    Err(message) => DaemonResponse {
                        id,
                        result: ResultPayload::Error { message },
                    },
                }
            }
            DaemonRequest::ExecuteCli { argv } => {
                let cli_result = execute_cli(&argv);
                DaemonResponse {
                    id,
                    result: ResultPayload::CliExecution {
                        stdout: cli_result.stdout,
                        stderr: cli_result.stderr,
                        exit_code: cli_result.exit_code,
                    },
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

        if is_shutdown {
            let _ = shutdown_tx.send(true);
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

    async fn wait_for_socket(socket_path: &std::path::Path) {
        let mut attempts = 0;
        while !socket_path.exists() && attempts < 50 {
            tokio::time::sleep(Duration::from_millis(10)).await;
            attempts += 1;
        }
    }

    async fn read_daemon_response(stream: UnixStream) -> serde_json::Value {
        let (read_half, _write_half) = stream.into_split();
        let mut reader = BufReader::new(read_half);
        let mut buf = String::new();
        reader.read_line(&mut buf).await.unwrap();
        serde_json::from_str(&buf).unwrap()
    }

    #[tokio::test]
    async fn daemon_execute_cli_version_returns_structured_response() {
        let temp_dir = tempfile::tempdir().unwrap();
        let socket_path = temp_dir.path().join("daemon.sock");
        let pid_path = temp_dir.path().join("daemon.pid");
        let (tx, rx) = tokio::sync::watch::channel(false);

        let socket = socket_path.clone();
        let pid = pid_path.clone();
        let shutdown_tx = tx.clone();
        let daemon_task = tokio::spawn(async move { run_daemon(&socket, &pid, tx, rx).await });

        wait_for_socket(&socket_path).await;

        let mut stream = UnixStream::connect(&socket_path).await.unwrap();
        stream
            .write_all(
                b"{\"id\":5,\"method\":\"ExecuteCli\",\"params\":{\"argv\":[\"version\"]}}\n",
            )
            .await
            .unwrap();

        let response = read_daemon_response(stream).await;
        assert_eq!(response["id"], 5);
        assert_eq!(response["result"]["status"], "CliExecution");
        assert_eq!(response["result"]["exit_code"], 0);
        assert_eq!(
            response["result"]["stdout"].as_str().unwrap().trim(),
            env!("CARGO_PKG_VERSION")
        );

        let _ = shutdown_tx.send(true);
        let result = tokio::time::timeout(Duration::from_secs(5), daemon_task).await;
        assert!(result.is_ok(), "daemon should complete within timeout");
        assert!(result.unwrap().is_ok(), "daemon should return Ok");
    }

    #[tokio::test]
    async fn daemon_execute_cli_unsupported_returns_structured_error() {
        let temp_dir = tempfile::tempdir().unwrap();
        let socket_path = temp_dir.path().join("daemon.sock");
        let pid_path = temp_dir.path().join("daemon.pid");
        let (tx, rx) = tokio::sync::watch::channel(false);

        let socket = socket_path.clone();
        let pid = pid_path.clone();
        let shutdown_tx = tx.clone();
        let daemon_task = tokio::spawn(async move { run_daemon(&socket, &pid, tx, rx).await });

        wait_for_socket(&socket_path).await;

        let mut stream = UnixStream::connect(&socket_path).await.unwrap();
        stream
            .write_all(b"{\"id\":6,\"method\":\"ExecuteCli\",\"params\":{\"argv\":[\"stats\"]}}\n")
            .await
            .unwrap();

        let response = read_daemon_response(stream).await;
        assert_eq!(response["id"], 6);
        assert_eq!(response["result"]["status"], "CliExecution");
        assert_eq!(response["result"]["exit_code"], 4);
        assert!(
            response["result"]["stderr"]
                .as_str()
                .unwrap()
                .contains("unsupported daemon CLI command: stats")
        );
        assert_eq!(response["result"]["stdout"].as_str().unwrap(), "");

        let _ = shutdown_tx.send(true);
        let result = tokio::time::timeout(Duration::from_secs(5), daemon_task).await;
        assert!(result.is_ok(), "daemon should complete within timeout");
        assert!(result.unwrap().is_ok(), "daemon should return Ok");
    }

    #[tokio::test]
    async fn daemon_stays_alive_after_execute_cli_success_and_error() {
        let temp_dir = tempfile::tempdir().unwrap();
        let socket_path = temp_dir.path().join("daemon.sock");
        let pid_path = temp_dir.path().join("daemon.pid");
        let (tx, rx) = tokio::sync::watch::channel(false);

        let socket = socket_path.clone();
        let pid = pid_path.clone();
        let shutdown_tx = tx.clone();
        let daemon_task = tokio::spawn(async move { run_daemon(&socket, &pid, tx, rx).await });

        wait_for_socket(&socket_path).await;

        let mut stream = UnixStream::connect(&socket_path).await.unwrap();
        stream
            .write_all(
                b"{\"id\":7,\"method\":\"ExecuteCli\",\"params\":{\"argv\":[\"version\"]}}\n",
            )
            .await
            .unwrap();
        let version_response = read_daemon_response(stream).await;
        assert_eq!(version_response["result"]["status"], "CliExecution");
        assert_eq!(version_response["result"]["exit_code"], 0);

        let mut stream = UnixStream::connect(&socket_path).await.unwrap();
        stream
            .write_all(b"{\"id\":8,\"method\":\"ExecuteCli\",\"params\":{\"argv\":[\"stats\"]}}\n")
            .await
            .unwrap();
        let error_response = read_daemon_response(stream).await;
        assert_eq!(error_response["result"]["status"], "CliExecution");
        assert_eq!(error_response["result"]["exit_code"], 4);

        let mut stream = UnixStream::connect(&socket_path).await.unwrap();
        stream
            .write_all(b"{\"id\":9,\"method\":\"Ping\"}\n")
            .await
            .unwrap();
        let ping_response = read_daemon_response(stream).await;
        assert_eq!(ping_response["id"], 9);
        assert_eq!(ping_response["result"]["status"], "Pong");

        let _ = shutdown_tx.send(true);
        let result = tokio::time::timeout(Duration::from_secs(5), daemon_task).await;
        assert!(result.is_ok(), "daemon should complete within timeout");
        assert!(result.unwrap().is_ok(), "daemon should return Ok");
    }
    fn init_git_repo(path: &std::path::Path) {
        std::fs::create_dir_all(path).unwrap();
        std::process::Command::new("git")
            .args(["init", "-q"])
            .current_dir(path)
            .output()
            .expect("git init should succeed");
    }

    fn write_project_allowlist(repo_root: &std::path::Path, exact_command: &str) {
        let orca_dir = repo_root.join(".orca");
        std::fs::create_dir_all(&orca_dir).unwrap();
        let allowlist = format!(
            r#"
[[allow]]
exact_command = "{exact_command}"
reason = "test allowlist"
"#
        );
        std::fs::write(orca_dir.join("allowlist.toml"), allowlist).unwrap();
    }

    #[test]
    fn resolve_evaluation_cwd_rejects_missing_cwd() {
        let err = resolve_evaluation_cwd(None).unwrap_err();
        assert!(err.contains("missing cwd"), "unexpected error: {err}");
    }

    #[test]
    fn resolve_evaluation_cwd_rejects_empty_cwd() {
        let err = resolve_evaluation_cwd(Some("   ")).unwrap_err();
        assert!(err.contains("missing cwd"), "unexpected error: {err}");
    }

    #[test]
    fn resolve_evaluation_cwd_rejects_nonexistent_path() {
        let err = resolve_evaluation_cwd(Some("/nonexistent/orca/cwd/test/path"))
            .unwrap_err();
        assert!(err.contains("invalid cwd"), "unexpected error: {err}");
        assert!(err.contains("does not exist"), "unexpected error: {err}");
    }

    #[test]
    fn resolve_evaluation_cwd_rejects_relative_path() {
        let err = resolve_evaluation_cwd(Some(".")).unwrap_err();
        assert!(err.contains("must be absolute"), "unexpected error: {err}");
        let err = resolve_evaluation_cwd(Some("subdir")).unwrap_err();
        assert!(err.contains("must be absolute"), "unexpected error: {err}");
    }

    #[test]
    fn resolve_evaluation_cwd_rejects_file_path() {
        let temp_dir = tempfile::tempdir().unwrap();
        let file_path = temp_dir.path().join("not-a-dir");
        std::fs::write(&file_path, b"x").unwrap();
        let err = resolve_evaluation_cwd(Some(&file_path.to_string_lossy())).unwrap_err();
        assert!(err.contains("invalid cwd"), "unexpected error: {err}");
        assert!(err.contains("not a directory"), "unexpected error: {err}");
    }

    #[tokio::test]
    async fn daemon_evaluate_missing_cwd_returns_error() {
        let temp_dir = tempfile::tempdir().unwrap();
        let socket_path = temp_dir.path().join("daemon.sock");
        let pid_path = temp_dir.path().join("daemon.pid");
        let (tx, rx) = tokio::sync::watch::channel(false);

        let socket = socket_path.clone();
        let pid = pid_path.clone();
        let shutdown_tx = tx.clone();
        let daemon_task = tokio::spawn(async move { run_daemon(&socket, &pid, tx, rx).await });

        wait_for_socket(&socket_path).await;

        let mut stream = UnixStream::connect(&socket_path).await.unwrap();
        stream
            .write_all(
                br#"{"id":10,"method":"Evaluate","params":{"command":"git status","cwd":null}}"#,
            )
            .await
            .unwrap();
        stream.write_all(b"\n").await.unwrap();

        let response = read_daemon_response(stream).await;
        assert_eq!(response["id"], 10);
        assert_eq!(response["result"]["status"], "Error");
        assert!(
            response["result"]["message"]
                .as_str()
                .unwrap()
                .contains("missing cwd")
        );

        let _ = shutdown_tx.send(true);
        let _ = tokio::time::timeout(Duration::from_secs(5), daemon_task).await;
    }

    #[tokio::test]
    async fn daemon_evaluate_invalid_cwd_returns_error() {
        let temp_dir = tempfile::tempdir().unwrap();
        let socket_path = temp_dir.path().join("daemon.sock");
        let pid_path = temp_dir.path().join("daemon.pid");
        let (tx, rx) = tokio::sync::watch::channel(false);

        let socket = socket_path.clone();
        let pid = pid_path.clone();
        let shutdown_tx = tx.clone();
        let daemon_task = tokio::spawn(async move { run_daemon(&socket, &pid, tx, rx).await });

        wait_for_socket(&socket_path).await;

        let mut stream = UnixStream::connect(&socket_path).await.unwrap();
        stream
            .write_all(
                br#"{"id":11,"method":"Evaluate","params":{"command":"git status","cwd":"/nonexistent/orca/cwd"}}"#,
            )
            .await
            .unwrap();
        stream.write_all(b"\n").await.unwrap();

        let response = read_daemon_response(stream).await;
        assert_eq!(response["id"], 11);
        assert_eq!(response["result"]["status"], "Error");
        assert!(
            response["result"]["message"]
                .as_str()
                .unwrap()
                .contains("invalid cwd")
        );

        let _ = shutdown_tx.send(true);
        let _ = tokio::time::timeout(Duration::from_secs(5), daemon_task).await;
    }

    #[tokio::test]
    async fn daemon_evaluate_uses_per_request_project_allowlist() {
        let temp_dir = tempfile::tempdir().unwrap();
        let repo_allowed = temp_dir.path().join("repo-a");
        let repo_denied = temp_dir.path().join("repo-b");
        init_git_repo(&repo_allowed);
        init_git_repo(&repo_denied);

        let cmd = "git reset --hard";
        write_project_allowlist(&repo_allowed, cmd);

        let socket_path = temp_dir.path().join("daemon.sock");
        let pid_path = temp_dir.path().join("daemon.pid");
        let (tx, rx) = tokio::sync::watch::channel(false);

        let socket = socket_path.clone();
        let pid = pid_path.clone();
        let shutdown_tx = tx.clone();
        let daemon_task = tokio::spawn(async move { run_daemon(&socket, &pid, tx, rx).await });

        wait_for_socket(&socket_path).await;

        let allowed_cwd = repo_allowed.canonicalize().unwrap();
        let denied_cwd = repo_denied.canonicalize().unwrap();

        let allow_req = format!(
            r#"{{"id":12,"method":"Evaluate","params":{{"command":"{cmd}","cwd":"{}"}}}}
"#,
            allowed_cwd.display()
        );
        let mut stream = UnixStream::connect(&socket_path).await.unwrap();
        stream.write_all(allow_req.as_bytes()).await.unwrap();
        let allow_response = read_daemon_response(stream).await;
        assert_eq!(allow_response["id"], 12);
        assert_eq!(allow_response["result"]["status"], "Allow");

        let deny_req = format!(
            r#"{{"id":13,"method":"Evaluate","params":{{"command":"{cmd}","cwd":"{}"}}}}
"#,
            denied_cwd.display()
        );
        let mut stream = UnixStream::connect(&socket_path).await.unwrap();
        stream.write_all(deny_req.as_bytes()).await.unwrap();
        let deny_response = read_daemon_response(stream).await;
        assert_eq!(deny_response["id"], 13);
        assert_eq!(deny_response["result"]["status"], "Deny");

        let _ = shutdown_tx.send(true);
        let result = tokio::time::timeout(Duration::from_secs(5), daemon_task).await;
        assert!(result.is_ok(), "daemon should complete within timeout");
        assert!(result.unwrap().is_ok(), "daemon should return Ok");
    }

    #[tokio::test]
    async fn daemon_shutdown_request_stops_daemon_and_removes_artifacts() {
        let temp_dir = tempfile::tempdir().unwrap();
        let socket_path = temp_dir.path().join("daemon.sock");
        let pid_path = temp_dir.path().join("daemon.pid");
        let (tx, rx) = tokio::sync::watch::channel(false);

        let socket = socket_path.clone();
        let pid = pid_path.clone();
        let shutdown_tx = tx.clone();
        let daemon_task = tokio::spawn(async move { run_daemon(&socket, &pid, tx, rx).await });

        wait_for_socket(&socket_path).await;
        assert!(pid_path.exists());

        let mut stream = UnixStream::connect(&socket_path).await.unwrap();
        stream
            .write_all(br#"{"id":20,"method":"Shutdown","params":null}"#)
            .await
            .unwrap();
        stream.write_all(b"\n").await.unwrap();

        let response = read_daemon_response(stream).await;
        assert_eq!(response["id"], 20);
        assert_eq!(response["result"]["status"], "Pong");

        let result = tokio::time::timeout(Duration::from_secs(5), daemon_task).await;
        assert!(result.is_ok(), "daemon should complete within timeout");
        assert!(result.unwrap().is_ok(), "daemon should return Ok");
        assert!(!socket_path.exists(), "socket should be removed after Shutdown");
        assert!(!pid_path.exists(), "pid file should be removed after Shutdown");
    }

    #[tokio::test]
    async fn daemon_no_longer_responds_to_ping_after_shutdown() {
        let temp_dir = tempfile::tempdir().unwrap();
        let socket_path = temp_dir.path().join("daemon.sock");
        let pid_path = temp_dir.path().join("daemon.pid");
        let (tx, rx) = tokio::sync::watch::channel(false);

        let socket = socket_path.clone();
        let pid = pid_path.clone();
        let shutdown_tx = tx.clone();
        let daemon_task = tokio::spawn(async move { run_daemon(&socket, &pid, tx, rx).await });

        wait_for_socket(&socket_path).await;

        let mut stream = UnixStream::connect(&socket_path).await.unwrap();
        stream
            .write_all(br#"{"id":21,"method":"Shutdown","params":null}"#)
            .await
            .unwrap();
        stream.write_all(b"\n").await.unwrap();
        let _ = read_daemon_response(stream).await;

        let _ = tokio::time::timeout(Duration::from_secs(5), daemon_task).await;

        let connect_result = UnixStream::connect(&socket_path).await;
        assert!(connect_result.is_err(), "socket should be gone after shutdown");
    }

    #[tokio::test]
    async fn daemon_repeated_shutdown_requests_are_safe() {
        let temp_dir = tempfile::tempdir().unwrap();
        let socket_path = temp_dir.path().join("daemon.sock");
        let pid_path = temp_dir.path().join("daemon.pid");
        let (tx, rx) = tokio::sync::watch::channel(false);

        let socket = socket_path.clone();
        let pid = pid_path.clone();
        let daemon_task = tokio::spawn(async move { run_daemon(&socket, &pid, tx, rx).await });

        wait_for_socket(&socket_path).await;

        let mut handles = Vec::with_capacity(3);
        for id in 30..33 {
            let sock = socket_path.clone();
            handles.push(tokio::spawn(async move {
                let mut stream = UnixStream::connect(&sock).await.unwrap();
                let req = format!(r#"{{"id":{id},"method":"Shutdown","params":null}}"#);
                stream.write_all(req.as_bytes()).await.unwrap();
                stream.write_all(b"\n").await.unwrap();
                read_daemon_response(stream).await
            }));
        }

        let mut pong_count = 0;
        for handle in handles {
            let response = handle.await.unwrap();
            if response["result"]["status"] == "Pong" {
                pong_count += 1;
            }
        }
        assert!(pong_count >= 1, "at least one Shutdown should be acknowledged");

        let result = tokio::time::timeout(Duration::from_secs(5), daemon_task).await;
        assert!(result.is_ok(), "daemon should complete within timeout");
        assert!(!socket_path.exists());
        assert!(!pid_path.exists());
    }

    #[tokio::test]
    async fn daemon_shutdown_during_active_evaluate_completes_response() {
        let temp_dir = tempfile::tempdir().unwrap();
        let socket_path = temp_dir.path().join("daemon.sock");
        let pid_path = temp_dir.path().join("daemon.pid");
        let (tx, rx) = tokio::sync::watch::channel(false);

        let socket = socket_path.clone();
        let pid = pid_path.clone();
        let shutdown_tx = tx.clone();
        let daemon_task = tokio::spawn(async move { run_daemon(&socket, &pid, tx, rx).await });

        wait_for_socket(&socket_path).await;

        let eval_cwd = temp_dir.path().canonicalize().unwrap();
        let allow_req = format!(
            r#"{{"id":40,"method":"Evaluate","params":{{"command":"ls -la","cwd":"{}"}}}}"#,
            eval_cwd.display()
        );
        let mut eval_stream = UnixStream::connect(&socket_path).await.unwrap();
        eval_stream.write_all(allow_req.as_bytes()).await.unwrap();
        eval_stream.write_all(b"\n").await.unwrap();
        let eval_response = read_daemon_response(eval_stream).await;
        assert_eq!(eval_response["id"], 40);
        assert_eq!(eval_response["result"]["status"], "Allow");

        let mut shutdown_stream = UnixStream::connect(&socket_path).await.unwrap();
        shutdown_stream
            .write_all(br#"{"id":41,"method":"Shutdown","params":null}"#)
            .await
            .unwrap();
        shutdown_stream.write_all(b"\n").await.unwrap();
        let shutdown_response = read_daemon_response(shutdown_stream).await;
        assert_eq!(shutdown_response["id"], 41);
        assert_eq!(shutdown_response["result"]["status"], "Pong");

        let _ = tokio::time::timeout(Duration::from_secs(5), daemon_task).await;
        assert!(!socket_path.exists());
        assert!(!pid_path.exists());
    }

    #[tokio::test]
    async fn daemon_malformed_request_returns_error_and_stays_alive() {
        let temp_dir = tempfile::tempdir().unwrap();
        let socket_path = temp_dir.path().join("daemon.sock");
        let pid_path = temp_dir.path().join("daemon.pid");
        let (tx, rx) = tokio::sync::watch::channel(false);

        let socket = socket_path.clone();
        let pid = pid_path.clone();
        let shutdown_tx = tx.clone();
        let daemon_task = tokio::spawn(async move { run_daemon(&socket, &pid, tx, rx).await });

        wait_for_socket(&socket_path).await;

        let mut stream = UnixStream::connect(&socket_path).await.unwrap();
        stream.write_all(b"{not valid json}\n").await.unwrap();
        let response = read_daemon_response(stream).await;
        assert_eq!(response["id"], 0);
        assert_eq!(response["result"]["status"], "Error");

        let mut ping_stream = UnixStream::connect(&socket_path).await.unwrap();
        ping_stream
            .write_all(br#"{"id":51,"method":"Ping"}"#)
            .await
            .unwrap();
        ping_stream.write_all(b"\n").await.unwrap();
        let ping_response = read_daemon_response(ping_stream).await;
        assert_eq!(ping_response["result"]["status"], "Pong");

        let _ = shutdown_tx.send(true);
        let _ = tokio::time::timeout(Duration::from_secs(5), daemon_task).await;
    }

}
