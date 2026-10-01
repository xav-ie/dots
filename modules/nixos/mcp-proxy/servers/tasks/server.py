"""MCP server for personal tasks: work that has no Jira ticket of its own.

Tasks live in one SQLite file ($TASKS_DB). Each has a key like TASK-12 so it
matches the same KEY-123 pattern Jira tickets use: a herdr tab or PR that
mentions TASK-12 links to it the same way CMFRT-1115 does. `links` holds
related Jira keys, PR refs, or URLs.
"""

import json
import os
import sqlite3
from datetime import datetime, timezone

from mcp.server.fastmcp import FastMCP

DB = os.environ["TASKS_DB"]
PREFIX = "TASK"
DONE = "Done"
mcp = FastMCP("tasks")

SCHEMA = """
CREATE TABLE IF NOT EXISTS tasks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  notes TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'To Do',
  priority TEXT NOT NULL DEFAULT 'Medium',
  merchant TEXT,
  links TEXT NOT NULL DEFAULT '[]',
  due TEXT,
  created TEXT NOT NULL,
  updated TEXT NOT NULL,
  done_at TEXT
)
"""


def db():
    conn = sqlite3.connect(DB)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute(SCHEMA)
    return conn


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def task_id(key):
    """Accept TASK-12, task-12 or 12."""
    tail = str(key).strip().upper().removeprefix(f"{PREFIX}-")
    if not tail.isdigit():
        raise ValueError(f"not a task key: {key!r} (expected {PREFIX}-<number>)")
    return int(tail)


def row(r):
    d = dict(r)
    d["key"] = f"{PREFIX}-{d['id']}"
    d["links"] = json.loads(d["links"])
    return d


def fetch(conn, key):
    r = conn.execute("SELECT * FROM tasks WHERE id = ?", (task_id(key),)).fetchone()
    if r is None:
        raise ValueError(f"no task {key}")
    return row(r)


@mcp.tool()
def list_tasks(include_done: bool = False, status: str | None = None, query: str | None = None) -> dict:
    """List tasks, most recently updated first. Done tasks are hidden unless
    include_done. status filters exactly; query matches title, notes, merchant
    and links case-insensitively."""
    sql, args = "SELECT * FROM tasks WHERE 1=1", []
    if not include_done:
        sql += " AND status != ?"
        args.append(DONE)
    if status:
        sql += " AND status = ?"
        args.append(status)
    if query:
        sql += " AND (title LIKE ? OR notes LIKE ? OR merchant LIKE ? OR links LIKE ?)"
        args += [f"%{query}%"] * 4
    with db() as conn:
        return {"tasks": [row(r) for r in conn.execute(sql + " ORDER BY updated DESC", args)]}


@mcp.tool()
def get_task(key: str) -> dict:
    """One task by key (TASK-12)."""
    with db() as conn:
        return fetch(conn, key)


@mcp.tool()
def create_task(
    title: str,
    notes: str = "",
    status: str = "To Do",
    priority: str = "Medium",
    merchant: str | None = None,
    links: list[str] | None = None,
    due: str | None = None,
) -> dict:
    """Create a task. status and priority use the Jira board's names (To Do,
    In Progress, Blocked, Backlog, Done; Highest..Lowest). links are related
    Jira keys, PR refs like bento-box#2152, or URLs. due is YYYY-MM-DD."""
    ts = now()
    with db() as conn:
        cur = conn.execute(
            "INSERT INTO tasks (title, notes, status, priority, merchant, links, due, created, updated, done_at)"
            " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (title, notes, status, priority, merchant, json.dumps(links or []), due, ts, ts, ts if status == DONE else None),
        )
        return fetch(conn, cur.lastrowid)


@mcp.tool()
def update_task(
    key: str,
    title: str | None = None,
    notes: str | None = None,
    status: str | None = None,
    priority: str | None = None,
    merchant: str | None = None,
    links: list[str] | None = None,
    due: str | None = None,
) -> dict:
    """Change the given fields; omitted fields stay as they are. Pass an empty
    string for merchant or due to clear it. links replaces the whole list."""
    changes = {"title": title, "notes": notes, "status": status, "priority": priority, "merchant": merchant, "due": due}
    fields = {k: (v or None) if k in ("merchant", "due") else v for k, v in changes.items() if v is not None}
    if links is not None:
        fields["links"] = json.dumps(links)
    if status is not None:
        fields["done_at"] = now() if status == DONE else None
    fields["updated"] = now()
    with db() as conn:
        fetch(conn, key)
        conn.execute(
            f"UPDATE tasks SET {', '.join(f'{k} = ?' for k in fields)} WHERE id = ?",
            [*fields.values(), task_id(key)],
        )
        return fetch(conn, key)


@mcp.tool()
def append_note(key: str, text: str) -> dict:
    """Add a timestamped line to the end of a task's notes (progress updates)."""
    with db() as conn:
        task = fetch(conn, key)
        stamp = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M")
        notes = f"{task['notes'].rstrip()}\n\n{stamp} {text}".lstrip()
        conn.execute("UPDATE tasks SET notes = ?, updated = ? WHERE id = ?", (notes, now(), task_id(key)))
        return fetch(conn, key)


@mcp.tool()
def delete_task(key: str) -> dict:
    """Permanently delete a task. Prefer update_task(status="Done") to finish one."""
    with db() as conn:
        task = fetch(conn, key)
        conn.execute("DELETE FROM tasks WHERE id = ?", (task_id(key),))
        return {"deleted": task["key"], "title": task["title"]}


if __name__ == "__main__":
    mcp.run()
