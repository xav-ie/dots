---
description: Send a Slack DM to a user by username. Looks up the user ID, then posts the message.
args:
  username:
    { type: string, description: "Slack username (without the leading @)" }
  message: { type: string, description: "Message body" }
tags: [slack, dm, messaging]
kind: code
---

const user = await tools.slack_mcp_server.users_lookupByName({
name: {{json username}},
})
await tools.slack_mcp_server.chat_postMessage({
channel: user.id,
text: {{json message}},
})
