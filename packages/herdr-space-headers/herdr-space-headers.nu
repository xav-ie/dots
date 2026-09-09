# Tag the first agent of each space with a `$space_header` metadata token, so the
# agent sidebar can carry a folder-style header row.
#
# herdr drops a sidebar row whose tokens all resolve to nothing (agent_rows in
# src/ui/sidebar/tokens.rs), and a `$name` token resolves only for panes that
# report it. So a row holding just `$space_header` renders on the entry this
# tags and vanishes on every other one — no blank lines, no per-entry repetition.
#
# The tag is refreshed on a loop with a TTL rather than cleared explicitly: when
# an agent stops being first in its space, its token simply expires.
const SOURCE = "herdr-space-headers"

# Shown on every agent that shares its tab with another.
const SPLIT_MARK = "◫"

def tag-agents [ttl_ms: int] {
  let labels = (
    herdr workspace list
    | from json
    | get result.workspaces
    | reduce -f {} {|w, acc| $acc | insert $w.workspace_id $w.label }
  )

  let agents = herdr agent list | from json | get result.agents

  # `agent list` walks workspaces then panes, the same traversal the sidebar
  # uses under agent_panel_sort = "spaces", so the first entry per workspace is
  # the one the panel shows on top.
  $agents
  | uniq-by workspace_id
  | each {|agent|
      let label = $labels | get -o $agent.workspace_id | default ""
      herdr pane report-metadata $agent.pane_id --source $SOURCE --token $"space_header=($label)" --ttl-ms $ttl_ms
    }
  | ignore

  # Agents sharing a tab render the same tab name, so mark them. Counted over
  # `pane list` rather than the agents above, because a plain shell splits the
  # tab just as much as a second agent does. Tabs holding one pane stay untagged
  # and the token resolves to nothing, keeping the common case unmarked.
  let panes_per_tab = (
    herdr pane list
    | from json
    | get result.panes
    | group-by tab_id
    | items {|tab, panes| {tab: $tab, count: ($panes | length)} }
    | reduce -f {} {|it, acc| $acc | insert $it.tab $it.count }
  )

  $agents
  | where {|agent| ($panes_per_tab | get -o $agent.tab_id | default 1) > 1 }
  | each {|agent|
      herdr pane report-metadata $agent.pane_id --source $SOURCE --token $"siblings=($SPLIT_MARK)" --ttl-ms $ttl_ms
    }
  | ignore
}

def main [
  --interval: duration = 2sec # How often to re-tag
  --ttl: duration = 6sec # How long a tag survives without a refresh
] {
  let ttl_ms = $ttl / 1ms | into int
  loop {
    # A herdr restart, or a pane closing mid-walk, must not kill the loop.
    try { tag-agents $ttl_ms }
    sleep $interval
  }
}
