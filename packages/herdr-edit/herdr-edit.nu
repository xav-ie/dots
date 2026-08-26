# Open a directory in a fresh herdr workspace running nvim. Takes the path
# positionally because Vibe Kanban's "Custom" editor appends it as the last
# argument.
def main [
  path: string # Directory (or file) to open
] {
  let dir = if ($path | path type) == "dir" { $path } else {
    $path | path dirname
  }

  let created = (
    herdr workspace create --cwd $dir --label ($dir | path basename) --focus
    | from json
  )

  # No "create a workspace running X" call exists; the command goes into the
  # root pane after it comes up on the default shell.
  herdr pane run $created.result.root_pane.pane_id nvim $path
}
