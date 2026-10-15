#!/usr/bin/env bash
# Two-day Google Calendar agenda (work + personal) as JSON [[{time,dur,acct,title}], [..]], cached 10 min.
cache="${XDG_CACHE_HOME:-$HOME/.cache}/hyprlock/agenda.json"
mkdir -p "$(dirname "$cache")"

fetch() {
  token=$(jq -r .token ~/.executor/server-control/auth.json)
  url=http://127.0.0.1:38972/mcp
  hdr=(-H "Authorization: Bearer $token" -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream')
  today=$(date +%F) tomorrow=$(date -d tomorrow +%F) after=$(date -d '2 days' +%F) tz=$(date +%:z)
  code=$(
    cat <<EOF
const days = ["$today", "$tomorrow"];
const accounts = {
  work: (a) => tools.google_workspace.org.work.calendar_listevents(a),
  personal: (a) => tools.google_workspace.org.personal.calendar_listevents(a),
};
const seen = new Set(), events = [];
for (const [acct, list] of Object.entries(accounts)) {
  const r = await list({ calendarId: "primary", timeMin: "${today}T00:00:00$tz", timeMax: "${after}T00:00:00$tz" });
  if (!r.ok) throw new Error(acct + ": " + r.error.message);
  const raw = r.data.structuredContent ?? r.data.content?.[0]?.text;
  for (const e of typeof raw === "string" ? JSON.parse(raw) : raw) {
    if (e.status === "cancelled" || seen.has(e.iCalUID ?? e.id)) continue;
    if ((e.attendees ?? []).some((a) => a.self && a.responseStatus === "declined")) continue;
    seen.add(e.iCalUID ?? e.id);
    events.push({ acct, title: e.summary ?? "(busy)", start: e.start.dateTime ?? e.start.date, end: e.end.dateTime ?? e.end.date, allDay: !e.start.dateTime });
  }
}
// ponytail: QuickJS has no Intl; Google returns dateTime in the calendar's zone (America/New_York), so read HH:MM off the string
const hm = (t) => { let [h, m] = t.slice(11, 16).split(":").map(Number); const ap = h < 12 ? "am" : "pm"; h = h % 12 || 12; return h + ":" + String(m).padStart(2, "0") + ap; };
const dur = (e) => {
  const mins = Math.round((Date.parse(e.end) - Date.parse(e.start)) / 60000);
  if (e.allDay) return mins > 1440 ? Math.round(mins / 1440) + "d" : "";
  if (mins >= 1440) return Math.round(mins / 1440) + "d";
  const h = Math.floor(mins / 60), m = mins % 60;
  return h ? (m ? h + "hr " + m + "min" : h + "hr") : m + "min";
};
return JSON.stringify(days.map((d, i) =>
  events
    .filter((e) => (e.allDay ? e.start <= d && e.end > d : e.start.slice(0, 10) === d))
    .sort((a, b) => (a.allDay ? "" : a.start).localeCompare(b.allDay ? "" : b.start))
    .map((e) => ({ time: e.allDay ? "all day" : hm(e.start), dur: dur(e), acct: e.acct, title: e.title.trim() })),
));
EOF
  )
  sid=$(curl -sS -m 5 -D - -o /dev/null "${hdr[@]}" "$url" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"hyprlock-agenda","version":"0"}}}' |
    tr -d '\r' | awk -F': ' 'tolower($1)=="mcp-session-id"{print $2}')
  body=$(jq -n --arg c "$code" '{jsonrpc:"2.0",id:2,method:"tools/call",params:{name:"execute",arguments:{code:$c}}}')
  res=$(curl -sS -m 20 "${hdr[@]}" -H "Mcp-Session-Id: $sid" "$url" -d "$body" | sed -n 's/^data: //p' |
    jq -r 'select(.id == 2) | .result.structuredContent | select(.status == "completed") | .result')
  [[ -n $res ]] && printf '%s\n' "$res" >"$cache"
}
# a failed fetch (offline after wake, executor down) falls back to the stale cache
if [[ ! -f $cache || $(($(date +%s) - $(stat -c %Y "$cache"))) -gt 600 ]]; then fetch || true; fi

cat "$cache"
