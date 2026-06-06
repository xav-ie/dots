# discord-mcp

An MCP server that drives a Discord **user account** (not a bot) via
[`discord.py-self`](https://github.com/dolfies/discord.py-self), exposing
messaging and unread-tracking tools over stdio.

Using a user token to automate an account is against Discord's Terms of
Service. This is built for personal, single-account accessibility use.

## Configuration

Set `DISCORD_USER_TOKEN` to your account token. The client connects lazily on
the first tool call and times out after 30s if it can't reach the gateway.

## Tools

**Messaging**

- `send_message(channel_id, content)` — send to any channel or DM; acks the
  channel afterwards, mirroring the web client.
- `read_messages(channel_id, limit=10)` — fetch recent messages (max 100).
- `edit_message(channel_id, message_id, new_content)`
- `delete_message(channel_id, message_id)`

**Discovery**

- `list_servers()` — guilds you're in.
- `list_channels(server_id)` — channels in a guild.
- `list_dms()` / `open_dm(user_id)` — direct-message channels.
- `find_user(query, server_id=None)` — resolve a user by name.

**Unread tracking**

Implements Discord's full notification cascade (channel override → per-guild
user setting → guild default), honouring mutes and `only_mentions`, so results
match what the web UI badges as unread:

- `list_unread_messages()` — every truly-unread channel across all guilds/DMs.
- `list_all_unread_servers()` — guilds that have unread badges.
- `list_server_unread(server_id)` — unread channels within one guild.
- `mark_as_read(channel_ids)` / `mark_server_as_read(server_ids)`

## Packaging notes

`default.nix` builds two dependencies absent from nixpkgs — `discord-protos`
(wheel) and `discord.py-self` (from GitHub) — and patches `curl_cffi` to
impersonate `chrome136`, the newest fingerprint the packaged
`curl-impersonate-chrome` supports.
