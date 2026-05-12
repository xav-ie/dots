#![deny(unused_crate_dependencies)]

use std::{net::SocketAddr, path::PathBuf, sync::Arc};

use anyhow::Context;
use clap::{Parser, ValueEnum};
use rmcp::ServiceExt;
use rmcp::transport::streamable_http_server::{
    StreamableHttpServerConfig, StreamableHttpService, session::local::LocalSessionManager,
};
use tokio_util::sync::CancellationToken;
use tracing_subscriber::{EnvFilter, layer::SubscriberExt, util::SubscriberInitExt};

mod refresh;
mod render;
mod server;
mod snippets;
mod types;

use crate::server::SnippetServer;
use crate::snippets::Registry;

#[derive(Debug, Clone, Copy, ValueEnum)]
enum Mode {
    Stdio,
    Http,
}

#[derive(Debug, Parser)]
#[command(
    name = "snippet-mcp",
    about = "MCP server exposing markdown snippets as searchable tools.",
    version
)]
struct Cli {
    /// Transport mode.
    #[arg(long, value_enum, default_value = "stdio")]
    mode: Mode,

    /// HTTP listen port (http mode only).
    #[arg(long, default_value_t = 38973)]
    port: u16,

    /// HTTP listen host (http mode only). Loopback by default; pass an explicit
    /// `0.0.0.0` for prod when behind a reverse proxy.
    #[arg(long, default_value = "127.0.0.1")]
    host: String,

    /// Override snippets directory. Default: $SNIPPET_DIR or /var/lib/snippet-mcp/snippets.
    #[arg(long)]
    dir: Option<PathBuf>,

    /// Additional host:port authorities to accept in the `Host` header.
    /// Loopback is allowed by default; add the public hostname when behind a
    /// reverse proxy (e.g. `--allowed-host snippets.lalala.casa`). Repeatable.
    #[arg(long = "allowed-host")]
    allowed_hosts: Vec<String>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    init_tracing();
    let cli = Cli::parse();

    let mode = cli.mode;

    let dir = cli
        .dir
        .or_else(|| std::env::var_os("SNIPPET_DIR").map(PathBuf::from))
        .unwrap_or_else(|| PathBuf::from("/var/lib/snippet-mcp/snippets"));

    let registry = Arc::new(Registry::new(dir.clone()));
    registry.ensure_dir().context("creating snippets dir")?;

    tracing::info!(dir = %dir.display(), ?mode, "snippet-mcp starting");

    match mode {
        Mode::Stdio => run_stdio(registry).await,
        Mode::Http => run_http(registry, cli.host, cli.port, cli.allowed_hosts).await,
    }
}

fn init_tracing() {
    let filter = EnvFilter::try_from_env("RUST_LOG")
        .unwrap_or_else(|_| EnvFilter::new("snippet_mcp=info,rmcp=warn"));
    tracing_subscriber::registry()
        .with(filter)
        .with(
            tracing_subscriber::fmt::layer()
                .with_writer(std::io::stderr)
                .with_target(false),
        )
        .init();
}

async fn run_stdio(registry: Arc<Registry>) -> anyhow::Result<()> {
    let server = SnippetServer::new(registry);
    let svc = server
        .serve((tokio::io::stdin(), tokio::io::stdout()))
        .await
        .context("starting stdio service")?;
    svc.waiting().await.context("stdio service ended")?;
    Ok(())
}

async fn run_http(
    registry: Arc<Registry>,
    host: String,
    port: u16,
    extra_hosts: Vec<String>,
) -> anyhow::Result<()> {
    let addr: SocketAddr = format!("{host}:{port}")
        .parse()
        .context("parsing bind address")?;
    let ct = CancellationToken::new();

    let mut config =
        StreamableHttpServerConfig::default().with_cancellation_token(ct.child_token());
    if !extra_hosts.is_empty() {
        let mut hosts = config.allowed_hosts.clone();
        hosts.extend(extra_hosts);
        config = config.with_allowed_hosts(hosts);
    }

    let service = StreamableHttpService::new(
        {
            let registry = registry.clone();
            move || Ok(SnippetServer::new(registry.clone()))
        },
        LocalSessionManager::default().into(),
        config,
    );

    let app = axum::Router::new()
        .nest_service("/mcp", service)
        .route("/health", axum::routing::get(health));

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .with_context(|| format!("binding {addr}"))?;
    tracing::info!(%addr, "snippet-mcp listening");

    let server_fut = axum::serve(listener, app).with_graceful_shutdown(async move {
        let _ = tokio::signal::ctrl_c().await;
        ct.cancel();
    });

    server_fut.await.context("axum serve")?;
    Ok(())
}

async fn health() -> axum::Json<serde_json::Value> {
    axum::Json(serde_json::json!({ "ok": true }))
}
