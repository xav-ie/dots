---
description: Multi-step triage of a Jira ticket — fetch context, label, transition to In Progress, assign to me.
args:
  ticket_id: { type: string, description: "Jira ticket key, e.g. ENG-1234" }
tags: [jira, triage, workflow]
kind: instructions
---

Run this sequence inside `executor.execute`:

1. `await tools.atlassian_mcp_product.get_issue({ key: {{json ticket_id}} })` — read the issue.
2. If status is "Open" or "To Do", call
   `tools.atlassian_mcp_product.transition_issue({ key: {{json ticket_id}}, transition: "In Progress" })`.
3. Add the `triaged` label:
   `tools.atlassian_mcp_product.update_issue({ key: {{json ticket_id}}, labels_add: ["triaged"] })`.
4. Assign to the current user:
   `tools.atlassian_mcp_product.assign_issue({ key: {{json ticket_id}}, assignee: "me" })`.
5. Post a confirmation comment summarizing what was done.

Stop and ask the user before step 4 if the assignee is already set to someone else.
