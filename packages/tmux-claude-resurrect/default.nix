{
  fetchFromGitHub,
  tmuxPlugins,
}:
# timvw/tmux-assistant-resurrect with a local patch making the send-keys
# restore content evaluate under nushell (the pane shell here).  The patch
# also disables the plugin's auto-install of Claude/OpenCode hooks because
# those mutate ~/.claude/settings.json, which is a mkOutOfStoreSymlink to a
# tracked file in this repo.  The Claude SessionStart/SessionEnd hooks are
# installed declaratively in home-manager/modules/claude/settings.json.
#
# Runtime PATH dependencies (jq, tmux, bash) are inherited from the calling
# shell — mkTmuxPlugin doesn't wrap scripts, so build-time inputs wouldn't
# reach the runtime PATH anyway.  jq is on system PATH via etc/profiles.
tmuxPlugins.mkTmuxPlugin {
  pluginName = "tmux-assistant-resurrect";
  # mkTmuxPlugin's default rtpFilePath substitutes dashes -> underscores in
  # pluginName, which doesn't match upstream's dashed filename.  Be explicit.
  rtpFilePath = "tmux-assistant-resurrect.tmux";
  version = "unstable-2026-05-22";
  src = fetchFromGitHub {
    owner = "timvw";
    repo = "tmux-assistant-resurrect";
    rev = "12dd6b54321eade8d66f59b3728f2f15d212d331";
    hash = "sha256-BjmfYyCzZGGnfYu5F9QhvIqcGVqhTPK90BjZ83q0+Wk=";
  };
  patches = [ ./nu_support.patch ];
}
