"""Discord.py-self client wrapper."""

import asyncio
import logging
import os
import sys

import discord

log = logging.getLogger(__name__)
log.setLevel(logging.DEBUG)
handler = logging.StreamHandler(sys.stderr)
handler.setFormatter(logging.Formatter("%(levelname)s %(name)s: %(message)s"))
log.addHandler(handler)

# Let discord.py log at INFO so we can see connection issues
logging.getLogger("discord").setLevel(logging.INFO)
logging.getLogger("discord").addHandler(handler)


class DiscordSelfClient(discord.Client):
    """Thin wrapper around discord.py-self Client."""

    def __init__(self) -> None:
        super().__init__()
        self._ready_event = asyncio.Event()

    async def on_ready(self) -> None:
        log.info("Logged in as %s (id=%s)", self.user, self.user.id)
        self._ready_event.set()

    async def on_connect(self) -> None:
        log.info("Connected to Discord gateway")

    async def on_disconnect(self) -> None:
        log.warning("Disconnected from Discord gateway")

    async def on_error(self, event: str, *args, **kwargs) -> None:
        log.error("Discord error in event %s: %s %s", event, args, kwargs)

    async def wait_until_ready(self) -> None:
        await self._ready_event.wait()


_client: DiscordSelfClient | None = None
_client_task: asyncio.Task | None = None


async def get_client() -> DiscordSelfClient:
    """Return the shared Discord client, starting it if needed."""
    global _client, _client_task

    if _client is not None and _client.is_ready():
        return _client

    token = os.environ.get("DISCORD_USER_TOKEN")
    if not token:
        raise RuntimeError("DISCORD_USER_TOKEN environment variable is not set")

    log.info("Starting Discord client (token length=%d)...", len(token))

    _client = DiscordSelfClient()

    # Wrap start in exception logger
    async def _start_with_logging() -> None:
        try:
            await _client.start(token)
        except Exception:
            log.exception("Discord client.start() failed")

    _client_task = asyncio.create_task(_start_with_logging())

    # Wait for the client to be fully connected
    try:
        await asyncio.wait_for(_client.wait_until_ready(), timeout=30)
    except asyncio.TimeoutError:
        log.error("Timed out after 30s waiting for Discord ready event")
        _client_task.cancel()
        _client = None
        _client_task = None
        raise RuntimeError("Timed out waiting for Discord connection")

    return _client
