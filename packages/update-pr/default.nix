{
  gh,
  pr-summary,
  writeNuApplication,
}:
writeNuApplication {
  name = "update-pr";
  runtimeInputs = [
    gh
    pr-summary
  ];
  text = # nu
    ''
      # Update PR based on commits
      def main [] {
        let current_body = (gh pr view --json body -q .body)
        let new_summary = (pr-summary)
        let start_marker = "<!-- PR_SUMMARY_START -->"
        let end_marker = "<!-- PR_SUMMARY_END -->"

        let updated_body = if ($current_body | str contains $start_marker) {
          let before = ($current_body | split row $start_marker | get 0)
          let after = ($current_body | split row $end_marker | get 1)
          $"($before)($start_marker)\n($new_summary)\n($end_marker)($after)"
        } else {
          $"($current_body)\n\n($start_marker)\n($new_summary)\n($end_marker)"
        }

        $updated_body | gh pr edit --body-file -
      }
    '';
}
