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

use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::watch;

use crate::daemon_protocol::{ClientEnvelope, DaemonRequest, DaemonResponse, ResultPayload};

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
                        tokio::spawn(handle_connection(stream));
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
                        tokio::spawn(handle_connection(stream));
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

async fn handle_connection(stream: UnixStream) {
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
                // Phase 0.5 placeholder: hardcoded regex until the real
                // evaluator is wired in Phase 5.
                let forbidden = regex_check(&command);
                if forbidden {
                    DaemonResponse {
                        id,
                        result: ResultPayload::Deny {
                            reason: "hardcoded placeholder: rm -rf / detected".to_string(),
                        },
                    }
                } else {
                    DaemonResponse {
                        id,
                        result: ResultPayload::Allow {
                            reason: "hardcoded placeholder: no destructive pattern matched"
                                .to_string(),
                        },
                    }
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

fn regex_check(command: &str) -> bool {
    // Simple literal substring check for the Phase 0.5 smoke test.
    command.contains("rm -rf")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn regex_check_detects_rm_rf() {
        assert!(regex_check("rm -rf /"));
        assert!(regex_check("  rm -rf  "));
        assert!(!regex_check("rm file.txt"));
        assert!(!regex_check("git status"));
    }
}
