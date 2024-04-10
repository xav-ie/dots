{ writeShellApplication, fzf }:
writeShellApplication {
  name = "g";
  runtimeInputs = [ fzf ];
  text = ''
    GIT_GRAPH_CMD="echo 'diff'; echo 'diff-cached'; git graph --color"

    while true; do
      # Append special lines to the git graph command output
      if ! (eval $GIT_GRAPH_CMD) | fzf --ansi --layout=reverse \
        --preview='sh -c "\
                    COMMIT_HASH=\$(echo \"{}\" | grep -o -e \"[a-zA-Z0-9]\\{7\\}\" | head -n 1); \
                    if [ -n \"\$COMMIT_HASH\" ]; then \
                      git show -p --stat --color \$COMMIT_HASH | delta; \
                    else \
                      if [ {} = \"diff\" ]; then \
                        git diff --color --stat && echo && git diff --color | delta; \
                      elif [ {} = \"diff-cached\" ]; then \
                        git diff --cached --color --stat && echo && git diff --cached --color | delta; \
                      else \
                        echo \"Commit hash not found.\"; \
                      fi; \
                    fi"' \
        --preview-window=down:80%:wrap \
        --bind=ctrl-d:preview-page-down \
        --bind=ctrl-u:preview-page-up \
        --bind="ctrl-r:reload:'\"$GIT_GRAPH_CMD\"'" \
        --header='Press CTRL+R to refresh'; then
        break
      fi
    done
  '';
}

