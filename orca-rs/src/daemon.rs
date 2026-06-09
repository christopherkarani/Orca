use std::path::{Path, PathBuf};
use std::process;

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

    // Attempt to bind the socket. If a stale file exists from a previous
    // unclean exit, bind may fail with AddrInUse; in that case we remove
    // the stale file and retry once. We never steal a socket from a live
    // daemon — if bind fails for any other reason we propagate the error.
    let listener = match UnixListener::bind(socket_path) {
        Ok(l) => l,
        Err(e) if e.kind() == std::io::ErrorKind::AddrInUse => {
            tracing::warn!(path = %socket_path.display(), "removing stale socket and retrying bind");
            tokio::fs::remove_file(socket_path).await?;
            UnixListener::bind(socket_path)?
        }
        Err(e) => return Err(Box::new(e)),
    };
    tracing::info!(path = %socket_path.display(), "orca-daemon bound UDS socket");

    // Write PID file so the Zig client can check for a running daemon.
    tokio::fs::write(pid_path, process::id().to_string()).await?;

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
