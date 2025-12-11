#!/usr/bin/env nu --stdin

def main [] {
  let input = $in | from json
  let model_display = $input.model.display_name
  let starship_prompt = ^starship prompt | str replace --all '\n' ''

  print $"($starship_prompt) ($model_display)"
}
