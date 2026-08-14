{
  ripgrep,
  writeNuApplication,
}:
writeNuApplication {
  name = "claude-resume";
  runtimeInputs = [ ripgrep ];
  text = # nu
    ''
      # Resume a Claude Code session from anywhere, by id.
      #
      # `claude --resume <id>` only looks at sessions for the current directory,
      # so resuming one recorded elsewhere fails unless you already know (and are
      # standing in) its directory. Transcripts live at
      # ~/.claude/projects/<cwd-with-every-non-alnum-as-dash>/<uuid>.jsonl, and
      # that directory name is lossy — a dash could have been /, . or _ — so the
      # directory is used to FIND the session and the transcript's own `cwd`
      # field is used to resume it.
      def transcripts [] {
        let base = ($env.CLAUDE_CONFIG_DIR? | default ([$env.HOME ".claude"] | path join)) | path join "projects"
        if not ($base | path exists) { return [] }
        ls ($"($base)/*/*.jsonl" | into glob) | sort-by modified -r
      }

      # First `cwd` in the transcript wins; it does not appear until a few lines
      # in, so this greps rather than parsing line 1. -m1 stops at the first hit
      # instead of reading a multi-MB file to the end.
      def session-cwd [file: path] {
        let hit = (rg -m1 -o --no-filename '"cwd":"[^"]*"' $file | complete)
        if $hit.exit_code != 0 { return null }
        $hit.stdout | lines | first | parse '"cwd":"{path}"' | get -o 0.path
      }

      # Resume the session whose id starts with `id`, from the directory it was
      # recorded in. With no arguments, lists every known session instead.
      def --wrapped main [
        id?: string # session id, or a unique prefix of one
        ...args     # extra flags passed through to claude
      ] {
        let all = transcripts

        if $id == null {
          return ($all | each {|f|
            {
              id: ($f.name | path basename | str replace ".jsonl" "")
              modified: $f.modified
              cwd: (session-cwd $f.name)
            }
          })
        }

        let matches = $all | where {|f| ($f.name | path basename) | str starts-with $id }

        if ($matches | is-empty) {
          error make --unspanned { msg: $"no session starting with '($id)'" }
        }

        # Ambiguity is the caller's to resolve: resuming the wrong session is
        # worse than being asked for another character of the id.
        if ($matches | length) > 1 {
          let listing = $matches | each {|f|
            let sid = $f.name | path basename | str replace ".jsonl" ""
            let when = $f.modified | format date "%Y-%m-%d %H:%M"
            $"  ($sid) \(($when)\)"
          } | str join "\n"
          error make --unspanned {
            msg: $"'($id)' matches ($matches | length) sessions:\n($listing)"
          }
        }

        let file = $matches | first | get name
        let session = $file | path basename | str replace ".jsonl" ""
        let dir = session-cwd $file

        if $dir == null {
          error make --unspanned { msg: $"($session): transcript records no cwd" }
        }
        if not ($dir | path exists) {
          error make --unspanned { msg: $"($session): recorded cwd no longer exists: ($dir)" }
        }

        cd $dir
        ^claude --resume $session ...$args
      }
    '';
}
