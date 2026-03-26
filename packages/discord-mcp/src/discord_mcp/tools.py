"""MCP tool implementations for Discord user-account automation."""

from __future__ import annotations

import asyncio

import discord

from .client import get_client


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _effective_notification_level(
    ch_settings,
    guild_settings,
    guild,
) -> discord.NotificationLevel:
    """Compute effective notification level via the Discord cascade.

    Channel override -> user guild override -> guild admin default.
    """
    if ch_settings is not None:
        level = ch_settings.level
        if level != discord.NotificationLevel.default:
            return level

    if guild_settings is not None:
        level = guild_settings.level
        if level != discord.NotificationLevel.default:
            return level

    if guild is not None:
        return guild.default_notifications

    return discord.NotificationLevel.all_messages


def _is_truly_unread(
    ch: discord.abc.Messageable,
    guild_settings=None,
    guild=None,
) -> tuple[bool, int]:
    """Check if a channel is truly unread, matching Discord web UI behavior.

    Returns (is_unread, badge_count). Implements the full notification cascade:
    1. Threads: must be joined (thread.me is not None)
    2. Threads: parent channel mute/notification settings apply
    3. Muted channel -> never unread
    4. Muted guild -> only unread if has mention badges
    5. Compute effective notification level (channel -> guild user -> guild default)
    6. all_messages (0): unread if any new messages
       only_mentions (1): unread only if badge_count > 0
       nothing (2): never unread
    """
    rs = ch.read_state
    if rs is None:
        return False, 0

    last_msg = getattr(ch, "last_message_id", None) or 0
    acked = rs.last_acked_id or 0
    badge = rs.badge_count
    has_new = last_msg > acked

    if not has_new and badge <= 0:
        return False, 0  # Nothing new at all

    # Get guild context
    if guild is None:
        guild = getattr(ch, "guild", None)
    if guild_settings is None and guild is not None:
        guild_settings = guild.notification_settings

    # Thread-specific checks
    if isinstance(ch, discord.Thread):
        # Must be a member of the thread to see unreads
        if ch.me is None:
            return False, 0

        # Parent channel settings apply to threads
        parent = ch.parent
        if parent is not None:
            parent_settings = getattr(parent, "notification_settings", None)
            if parent_settings is not None:
                # Parent muted -> thread is muted
                if parent_settings.muted:
                    return False, 0
                # Parent notification level applies
                effective = _effective_notification_level(
                    parent_settings, guild_settings, guild
                )
                if effective == discord.NotificationLevel.nothing:
                    return False, 0
                if effective == discord.NotificationLevel.only_mentions:
                    return badge > 0, badge

        # If we get here for a thread, check guild mute then allow
        if guild_settings is not None and guild_settings.muted:
            return badge > 0, badge
        return True, badge

    # Non-thread channel checks
    ch_settings = getattr(ch, "notification_settings", None)
    if ch_settings is not None and ch_settings.muted:
        return False, 0  # Muted channels never show as unread

    if guild_settings is not None and guild_settings.muted:
        # Muted guilds only show mention badges in sidebar
        return badge > 0, badge

    effective = _effective_notification_level(ch_settings, guild_settings, guild)

    if effective == discord.NotificationLevel.all_messages:
        return True, badge
    elif effective == discord.NotificationLevel.only_mentions:
        return badge > 0, badge
    else:  # nothing / none
        return False, 0


def _channel_display_name(ch: discord.abc.Messageable) -> str:
    """Return a human-readable name for any channel type."""
    if isinstance(ch, discord.DMChannel):
        r = ch.recipient
        return f"DM with {r.display_name}" if r else f"DM (channel {ch.id})"
    if isinstance(ch, discord.GroupChannel):
        names = ", ".join(r.display_name for r in ch.recipients)
        return f"Group: {names}"
    if isinstance(ch, discord.Thread):
        parent = ch.parent
        parent_name = f"#{parent.name}" if parent else "unknown"
        guild_name = ch.guild.name if ch.guild else ""
        return f"{parent_name} > {ch.name} in {guild_name}"
    # Guild channel
    guild_name = ch.guild.name if hasattr(ch, "guild") and ch.guild else ""
    ch_name = getattr(ch, "name", str(ch.id))
    return f"#{ch_name} in {guild_name}" if guild_name else f"#{ch_name}"


# ---------------------------------------------------------------------------
# Message management
# ---------------------------------------------------------------------------


async def send_message(channel_id: str, content: str) -> str:
    """Send a message to any channel or DM as your Discord account.

    Args:
        channel_id: The Discord channel ID to send the message to.
        content: The message text to send.

    Returns:
        Confirmation with the sent message ID.
    """
    client = await get_client()
    channel = client.get_channel(int(channel_id))
    if channel is None:
        channel = await client.fetch_channel(int(channel_id))
    msg = await channel.send(content)

    # Mark channel as read (mirrors Discord web app behavior)
    rs = getattr(channel, "read_state", None)
    if rs is not None:
        try:
            await rs.ack(msg.id)
        except Exception:
            pass  # Non-critical; don't fail the send

    return f"Message sent (id={msg.id}) in #{getattr(channel, 'name', channel_id)}"


async def read_messages(channel_id: str, limit: int = 10) -> str:
    """Read recent messages from a channel or DM.

    Args:
        channel_id: The Discord channel ID to read from.
        limit: Number of recent messages to fetch (default 10, max 100).

    Returns:
        Formatted list of recent messages with author, timestamp, and content.
    """
    client = await get_client()
    channel = client.get_channel(int(channel_id))
    if channel is None:
        channel = await client.fetch_channel(int(channel_id))

    limit = min(max(1, limit), 100)
    messages: list[discord.Message] = []
    async for msg in channel.history(limit=limit):
        messages.append(msg)

    if not messages:
        return "No messages found."

    lines: list[str] = []
    for msg in reversed(messages):
        ts = msg.created_at.strftime("%Y-%m-%d %H:%M")
        author = msg.author.display_name
        text = msg.content or "(no text content)"
        lines.append(f"[{ts}] {author}: {text}  (id={msg.id})")
    return "\n".join(lines)


async def edit_message(channel_id: str, message_id: str, new_content: str) -> str:
    """Edit one of your own messages.

    Args:
        channel_id: The channel the message is in.
        message_id: The ID of the message to edit.
        new_content: The new message text.

    Returns:
        Confirmation that the message was edited.
    """
    client = await get_client()
    channel = client.get_channel(int(channel_id))
    if channel is None:
        channel = await client.fetch_channel(int(channel_id))
    msg = await channel.fetch_message(int(message_id))
    if msg.author.id != client.user.id:
        return "Error: you can only edit your own messages."
    await msg.edit(content=new_content)
    return f"Message {message_id} edited."


async def delete_message(channel_id: str, message_id: str) -> str:
    """Delete a message.

    Args:
        channel_id: The channel the message is in.
        message_id: The ID of the message to delete.

    Returns:
        Confirmation that the message was deleted.
    """
    client = await get_client()
    channel = client.get_channel(int(channel_id))
    if channel is None:
        channel = await client.fetch_channel(int(channel_id))
    msg = await channel.fetch_message(int(message_id))
    await msg.delete()
    return f"Message {message_id} deleted."


# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------


async def list_servers() -> str:
    """List all Discord servers you are a member of.

    Returns:
        Formatted list of servers with name, ID, and member count.
    """
    client = await get_client()
    if not client.guilds:
        return "You are not in any servers."

    lines: list[str] = []
    for guild in sorted(client.guilds, key=lambda g: g.name.lower()):
        lines.append(f"- {guild.name}  (id={guild.id}, members={guild.member_count})")
    return "\n".join(lines)


async def list_channels(server_id: str) -> str:
    """List all channels in a Discord server.

    Args:
        server_id: The Discord server (guild) ID.

    Returns:
        Formatted list of channels grouped by category.
    """
    client = await get_client()
    guild = client.get_guild(int(server_id))
    if guild is None:
        return f"Server {server_id} not found."

    lines: list[str] = []
    categorized: dict[str | None, list[discord.abc.GuildChannel]] = {}
    for ch in sorted(guild.channels, key=lambda c: (c.position, c.name)):
        if isinstance(ch, discord.CategoryChannel):
            continue
        cat_name = ch.category.name if ch.category else "(no category)"
        categorized.setdefault(cat_name, []).append(ch)

    for cat, channels in sorted(categorized.items(), key=lambda x: x[0] or ""):
        lines.append(f"\n{cat}:")
        for ch in channels:
            kind = "text" if isinstance(ch, discord.TextChannel) else type(ch).__name__
            lines.append(f"  - #{ch.name}  (id={ch.id}, type={kind})")

    return "\n".join(lines)


async def list_server_unread(server_id: str) -> str:
    """List all unread channels in a server with a preview of recent messages.

    Checks every text channel in the server for unread activity using in-memory
    read state data, then fetches a short preview from each unread channel.
    This lets you catch up on an entire server in one call.

    Args:
        server_id: The Discord server (guild) ID.

    Returns:
        Summary of all channels with unread messages, grouped by category,
        with message previews and channel IDs for follow-up actions.
    """
    client = await get_client()
    guild = client.get_guild(int(server_id))
    if guild is None:
        return f"Server {server_id} not found."

    # Collect channels with unread activity (respects mute settings)
    guild_settings = guild.notification_settings
    unread_channels: list[tuple[str, str, discord.abc.Messageable, int]] = []

    for ch in guild.channels:
        if not isinstance(ch, (discord.TextChannel, discord.VoiceChannel)):
            continue
        perms = ch.permissions_for(guild.me)
        if not perms.read_messages or not perms.read_message_history:
            continue

        is_unread, badges = _is_truly_unread(ch, guild_settings, guild)
        if is_unread:
            cat_name = ch.category.name if ch.category else "(no category)"
            unread_channels.append((cat_name, f"#{ch.name}", ch, badges))

    # Also check active threads (cached, no API calls)
    for thread in guild.threads:
        if thread.archived:
            continue

        is_unread, badges = _is_truly_unread(thread, guild_settings, guild)
        if is_unread:
            parent = thread.parent
            parent_name = f"#{parent.name}" if parent else "unknown"
            cat_name = (
                parent.category.name if parent and parent.category else "(no category)"
            )
            display = f"{parent_name} > {thread.name}"
            unread_channels.append((cat_name, display, thread, badges))

    if not unread_channels:
        return f"No unread channels in {guild.name}."

    # Sort by category, then display name
    unread_channels.sort(key=lambda x: (x[0], x[1]))

    # Fetch previews for each unread channel
    sections: list[str] = []
    current_cat = None

    for cat_name, display, ch, badge in unread_channels:
        if cat_name != current_cat:
            current_cat = cat_name
            sections.append(f"\n{cat_name}:")

        badge_str = f", {badge} mentions" if badge > 0 else ""
        header = f"  {display}  (channel_id={ch.id}{badge_str})"
        sections.append(header)

        # Fetch last few messages as preview
        try:
            messages: list[discord.Message] = []
            async for msg in ch.history(limit=5):
                messages.append(msg)

            if messages:
                for msg in reversed(messages):
                    ts = msg.created_at.strftime("%Y-%m-%d %H:%M")
                    author = msg.author.display_name
                    preview = (msg.content or "(no text)").replace("\n", " ")[:100]
                    sections.append(f"    [{ts}] {author}: {preview}")
            else:
                sections.append("    (no recent messages)")
        except discord.Forbidden:
            sections.append("    (no access)")
        except Exception as e:
            sections.append(f"    (error: {e})")

    return f"Unread channels in {guild.name}:\n" + "\n".join(sections)


async def find_user(query: str, server_id: str | None = None) -> str:
    """Search for a Discord user by name. Searches across your servers or within a specific server.

    Args:
        query: The username or display name to search for (case-insensitive partial match).
        server_id: Optional server ID to limit the search to a specific server.

    Returns:
        Formatted list of matching users with name, ID, and where they were found.
    """
    client = await get_client()
    query_lower = query.lower()
    seen: set[int] = set()
    results: list[str] = []

    guilds = [client.get_guild(int(server_id))] if server_id else client.guilds
    guilds = [g for g in guilds if g is not None]

    for guild in guilds:
        for member in guild.members:
            if member.id in seen:
                continue
            name = member.name or ""
            display = member.display_name or ""
            global_name = member.global_name or ""
            if (
                query_lower in name.lower()
                or query_lower in display.lower()
                or query_lower in global_name.lower()
            ):
                seen.add(member.id)
                results.append(
                    f"- {member.display_name} (@{member.name})  "
                    f"(id={member.id}, server={guild.name})"
                )

    if not results:
        return f'No users found matching "{query}".'

    return "\n".join(results)


async def list_all_unread_servers() -> str:
    """List all servers that have unread channels or threads.

    Entirely in-memory — iterates cached guilds, channels, and active threads.
    No API calls. Use this to decide which server to dive into with
    list_server_unread.

    Returns:
        Summary of each server with unread activity: channel count, mention
        count, and server ID for follow-up.
    """
    client = await get_client()

    unread_servers: list[tuple[int, str]] = []

    for guild in client.guilds:
        guild_settings = guild.notification_settings
        unread_count = 0
        mention_count = 0

        # Check channels
        for ch in guild.channels:
            if not isinstance(ch, (discord.TextChannel, discord.VoiceChannel)):
                continue
            is_unread, badges = _is_truly_unread(ch, guild_settings, guild)
            if is_unread:
                unread_count += 1
                mention_count += badges

        # Check active threads (cached)
        for thread in guild.threads:
            if thread.archived:
                continue
            is_unread, badges = _is_truly_unread(thread, guild_settings, guild)
            if is_unread:
                unread_count += 1
                mention_count += badges

        if unread_count > 0:
            mention_str = f", {mention_count} mentions" if mention_count > 0 else ""
            unread_servers.append(
                (
                    unread_count,
                    f"- {guild.name}: {unread_count} unread"
                    f"{mention_str}  (server_id={guild.id})",
                )
            )

    if not unread_servers:
        return "No servers with unread activity."

    # Sort by unread count descending
    unread_servers.sort(key=lambda x: x[0], reverse=True)
    return "\n".join(line for _, line in unread_servers)


async def list_unread_messages() -> str:
    """List unread DMs and recent mentions across all servers.

    Combines two sources:
    1. Unread DMs/group DMs — uses in-memory read state (badge_count > 0).
    2. Recent mentions — fetches up to 25 recent mentions from the past week
       across all servers and DMs.

    Returns:
        Formatted summary of unread DMs and recent mentions, with channel/user
        info and message previews.
    """
    client = await get_client()
    sections: list[str] = []

    # --- Unread DMs (in-memory, no API calls) ---
    unread: list[tuple[int, str]] = []
    for ch in client.private_channels:
        rs = ch.read_state
        if rs is None or rs.badge_count <= 0:
            continue

        if isinstance(ch, discord.DMChannel):
            recipient = ch.recipient
            name = recipient.display_name if recipient else "Unknown"
            username = f"@{recipient.name}" if recipient else "@?"
            user_id = recipient.id if recipient else "?"
            unread.append(
                (
                    rs.badge_count,
                    f"- {name} ({username})  "
                    f"(channel_id={ch.id}, user_id={user_id}, unread={rs.badge_count})",
                )
            )
        elif isinstance(ch, discord.GroupChannel):
            names = ", ".join(r.display_name for r in ch.recipients)
            unread.append(
                (
                    rs.badge_count,
                    f"- Group: {names}  (channel_id={ch.id}, unread={rs.badge_count})",
                )
            )

    if unread:
        unread.sort(key=lambda x: x[0], reverse=True)
        sections.append("UNREAD DMs:\n" + "\n".join(line for _, line in unread))
    else:
        sections.append("UNREAD DMs:\n(none)")

    # --- Unread mentions (API call, up to 25 from past week) ---
    # Filter to only mentions newer than the channel's last acked message.
    mentions: list[str] = []
    seen_ids: set[int] = set()
    async for msg in client.recent_mentions(limit=25):
        if msg.id in seen_ids:
            continue
        seen_ids.add(msg.id)

        # Skip mentions we've already read
        ch = msg.channel
        rs = getattr(ch, "read_state", None)
        if rs is not None and rs.last_acked_id is not None:
            if msg.id <= rs.last_acked_id:
                continue

        ts = msg.created_at.strftime("%Y-%m-%d %H:%M")
        author = msg.author.display_name
        preview = (msg.content or "(no text)")[:120]
        location = _channel_display_name(ch)

        mentions.append(
            f"- [{ts}] {author} in {location}: {preview}  "
            f"(channel_id={ch.id}, message_id={msg.id})"
        )

    if mentions:
        sections.append("UNREAD MENTIONS:\n" + "\n".join(mentions))
    else:
        sections.append("UNREAD MENTIONS:\n(none)")

    return "\n\n".join(sections)


async def mark_as_read(channel_ids: list[str]) -> str:
    """Mark one or more channels/DMs/threads as read.

    Uses the raw POST /read-states/ack-bulk API for reliability.
    Accepts channel IDs from the output of list_unread_messages or
    list_server_unread.

    Args:
        channel_ids: List of channel ID strings to mark as read.

    Returns:
        Confirmation of which channels were marked as read.
    """
    client = await get_client()
    states: list[dict] = []
    results: list[str] = []

    for cid_str in channel_ids:
        cid = int(cid_str)
        channel = client.get_channel(cid)
        if channel is None:
            try:
                channel = await client.fetch_channel(cid)
            except Exception:
                results.append(f"- Channel {cid_str}: not found, skipped")
                continue

        last_msg_id = getattr(channel, "last_message_id", None)
        if last_msg_id is None:
            results.append(f"- {_channel_display_name(channel)}: no messages to ack")
            continue

        states.append(
            {
                "channel_id": cid,
                "message_id": last_msg_id,
                "read_state_type": 0,
            }
        )
        results.append(f"- {_channel_display_name(channel)}: marked as read")

    if states:
        try:
            await asyncio.wait_for(client.http.ack_bulk(states), timeout=15)
        except asyncio.TimeoutError:
            results.append("  (warning: bulk ack timed out, some may not be marked)")
        except Exception as e:
            results.append(f"  (warning: bulk ack failed: {e})")

    if not results:
        return "No channels to mark as read."

    return "\n".join(results)


def _collect_unread_states(guild: discord.Guild) -> list[dict]:
    """Collect unread channel/thread read states as raw bulk ack payloads."""
    states: list[dict] = []

    for ch in guild.channels:
        if not isinstance(ch, (discord.TextChannel, discord.VoiceChannel)):
            continue
        rs = ch.read_state
        if rs is None or ch.last_message_id is None:
            continue
        has_unread = rs.badge_count > 0 or (
            rs.last_acked_id is not None and ch.last_message_id > rs.last_acked_id
        )
        if has_unread:
            states.append(
                {
                    "channel_id": ch.id,
                    "message_id": ch.last_message_id,
                    "read_state_type": 0,  # ReadStateType.channel
                }
            )

    for thread in guild.threads:
        if thread.archived:
            continue
        rs = thread.read_state
        if rs is None or thread.last_message_id is None:
            continue
        has_unread = rs.badge_count > 0 or (
            rs.last_acked_id is not None and thread.last_message_id > rs.last_acked_id
        )
        if has_unread:
            states.append(
                {
                    "channel_id": thread.id,
                    "message_id": thread.last_message_id,
                    "read_state_type": 0,
                }
            )

    return states


async def mark_server_as_read(server_ids: list[str]) -> str:
    """Mark all channels and threads in one or more servers as read.

    Collects unread channel/thread states in-memory, then uses the raw
    POST /read-states/ack-bulk API directly. Falls back to per-guild ack
    if bulk fails.

    Args:
        server_ids: List of server (guild) ID strings to mark as read.

    Returns:
        Confirmation of which servers were marked as read.
    """
    client = await get_client()
    results: list[str] = []

    # Collect all unread states across all requested guilds
    all_states: list[dict] = []
    guild_counts: list[tuple[str, int]] = []
    not_found: list[str] = []

    for sid_str in server_ids:
        guild = client.get_guild(int(sid_str))
        if guild is None:
            not_found.append(f"- Server {sid_str}: not found, skipped")
            continue

        states = _collect_unread_states(guild)
        if states:
            guild_counts.append((guild.name, len(states)))
            all_states.extend(states)
        else:
            results.append(f"- {guild.name}: already read")

    results = not_found + results

    if all_states:
        # Batch in chunks of 100 to stay safe with API limits
        for i in range(0, len(all_states), 100):
            batch = all_states[i : i + 100]
            try:
                await asyncio.wait_for(client.http.ack_bulk(batch), timeout=15)
            except asyncio.TimeoutError:
                results.append(
                    f"  (batch {i // 100 + 1} timed out, "
                    f"{len(batch)} channels may not be marked)"
                )
            except Exception as e:
                results.append(f"  (batch {i // 100 + 1} failed: {e})")

        for name, count in guild_counts:
            results.append(f"- {name}: marked {count} channels/threads as read")

    if not results:
        return "No servers to mark as read."

    return "\n".join(results)


async def list_dms() -> str:
    """List your open DM conversations.

    Returns:
        Formatted list of DM channels with recipient names, IDs, and last message preview.
    """
    client = await get_client()

    if not client.private_channels:
        return "No open DM conversations."

    lines: list[str] = []
    for ch in client.private_channels:
        if isinstance(ch, discord.DMChannel):
            recipient = ch.recipient
            name = recipient.display_name if recipient else "Unknown"
            user_id = recipient.id if recipient else "?"
            lines.append(
                f"- {name} (@{recipient.name if recipient else '?'})  "
                f"(channel_id={ch.id}, user_id={user_id})"
            )
        elif isinstance(ch, discord.GroupChannel):
            names = ", ".join(r.display_name for r in ch.recipients)
            lines.append(f"- Group: {names}  (channel_id={ch.id})")

    if not lines:
        return "No open DM conversations."

    return "\n".join(lines)


async def open_dm(user_id: str) -> str:
    """Open or get a DM channel with a user. Use this to get a channel_id for sending DMs.

    Args:
        user_id: The Discord user ID to open a DM with.

    Returns:
        The DM channel ID that can be used with send_message and read_messages.
    """
    client = await get_client()
    user = client.get_user(int(user_id))
    if user is None:
        user = await client.fetch_user(int(user_id))
    dm = await user.create_dm()
    return f"DM channel opened with {user.display_name} (@{user.name})  (channel_id={dm.id})"
