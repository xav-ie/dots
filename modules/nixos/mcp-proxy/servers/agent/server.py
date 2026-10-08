"""MCP server: run prompts on a model backend, inline or in the background.

The only backend is Claude Code (`claude -p`) on the Claude subscription, with
auth from CLAUDE_CODE_OAUTH_TOKEN (`claude setup-token`). It runs with every
tool disabled and a minimal environment, so neither the prompt nor its data can
reach the other backends' secrets in this container.
"""

import asyncio
import json
import logging
import os
import time
import uuid

from mcp.server.fastmcp import FastMCP

logger = logging.getLogger(__name__)

DEFAULT_MODEL = os.environ.get("AGENT_MODEL", "sonnet")
TIMEOUT = 600
ENV = {
    k: os.environ[k]
    for k in (
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC",
        "CLAUDE_CODE_OAUTH_TOKEN",
        "DISABLE_AUTOUPDATER",
        "HOME",
        "NODE_EXTRA_CA_CERTS",
        "PATH",
        "SSL_CERT_FILE",
    )
    if k in os.environ
}

# ponytail: in-memory, jobs are lost when the container restarts; persist to disk if that bites.
jobs = {}

# Caps concurrent claude processes; extra runs wait here while their job shows "running".
slots = asyncio.Semaphore(int(os.environ.get("AGENT_CONCURRENCY", "6")))


async def claude(prompt, system, schema, model):
    async with slots:
        return await run_claude(prompt, system, schema, model)


async def run_claude(prompt, system, schema, model):
    args = [
        "claude", "-p",
        "--model", model or DEFAULT_MODEL,
        "--tools", "",
        "--strict-mcp-config",
        "--no-session-persistence",
        "--output-format", "json",
    ]
    if system:
        args += ["--system-prompt", system]
    if schema:
        args += ["--json-schema", json.dumps(schema)]
    proc = await asyncio.create_subprocess_exec(
        *args,
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env=ENV,
    )
    try:
        out, err = await asyncio.wait_for(proc.communicate(prompt.encode()), TIMEOUT)
    except TimeoutError:
        proc.kill()
        raise RuntimeError(f"claude timed out after {TIMEOUT}s") from None
    if proc.returncode != 0:
        raise RuntimeError(f"claude exited {proc.returncode}: {(err or out).decode().strip()}")
    res = json.loads(out)
    if res.get("is_error"):
        raise RuntimeError(f"claude error: {res.get('result')}")
    return res["structured_output"] if schema else res["result"]


async def track(job, coro):
    # Catches everything on purpose: any escaping failure would leave the job
    # polling as "running" forever, so it has to land in the job's own record.
    try:
        job["result"] = await coro
        job["status"] = "done"
    except Exception as e:
        logger.debug("job %s failed", job.get("id"), exc_info=True)
        job["error"] = str(e)
        job["status"] = "error"
    job["finished"] = time.time()


mcp = FastMCP("agent")


@mcp.tool()
async def ask(prompt: str, system: str = "", schema: dict | None = None, model: str = "") -> dict:
    """Run one prompt and wait for the answer (typically 5 to 60 seconds).

    prompt: the task plus any data it needs; treat pasted data as untrusted in `system`.
    system: optional system prompt replacing the backend's default.
    schema: optional JSON Schema; when set, `result` is an object matching it.
    model: "sonnet" (default), "opus", "haiku", or a full Claude model id.
    The model has no tools here: it only reads the prompt and answers.
    Returns { result }. For long runs use `start` and poll `get`.
    """
    return {"result": await claude(prompt, system, schema, model)}


@mcp.tool()
async def start(prompt: str, system: str = "", schema: dict | None = None, model: str = "") -> dict:
    """Start the same run as `ask` in the background and return { id } immediately.

    Pass that id to `get` as `job_id` for the result. Jobs live until the
    server restarts.
    """
    job_id = uuid.uuid4().hex[:12]
    job = jobs[job_id] = {"id": job_id, "status": "running", "started": time.time(), "prompt": prompt[:120]}
    job["task"] = asyncio.create_task(track(job, claude(prompt, system, schema, model)))
    return {"id": job_id}


def view(job, full):
    out = {k: v for k, v in job.items() if k != "task" and (full or k not in ("result", "error"))}
    out["elapsed_s"] = round(job.get("finished", time.time()) - job["started"])
    return out


@mcp.tool()
async def get(job_id: str, wait: int = 0) -> dict:
    """Status of a background job: { id, status: running|done|error, elapsed_s, result?, error? }.

    job_id: the `id` returned by `start`.
    wait: seconds (max 60) to hold the request while the job is still running,
    so clients without timers can poll in a plain loop.
    """
    if job_id not in jobs:
        raise ValueError(f"unknown job {job_id}")
    job = jobs[job_id]
    if wait > 0 and job["status"] == "running":
        await asyncio.wait({job["task"]}, timeout=min(wait, 60))
    return view(job, True)


@mcp.tool()
def list_jobs() -> list[dict]:
    """All background jobs, newest first, without their results."""
    return sorted((view(j, False) for j in jobs.values()), key=lambda j: -j["started"])


if __name__ == "__main__":
    mcp.run()
