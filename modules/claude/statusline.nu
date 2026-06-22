#!/usr/bin/env -S nu --stdin

def main [] {
  let input = $in | from json
  let model_display = $input.model.display_name
  # prompt-render comes from nu_plugin_prompt — in-process, no subprocess
  let prompt = prompt-render | str replace --all '\n' ''

  print $"($prompt) ($model_display)"
}
