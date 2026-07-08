# log oneline commits with associated prs, max of 10 to reduce api usage.
def --wrapped main [...args] {
  let commits = (^git log --oneline -n 10 ...$args  | lines | par-each -k {|| $in | split row ' ' -n 2})

  let data = $commits | par-each -k {|commit|
    let associated_prs = (gh pr list --state all --limit 5 --search $"($commit.0)" --json title,headRefName,url | from json)
    let prs_cleaned = $associated_prs | par-each -k {|pr|
      {
        title: (if ($pr.title == $pr.headRefName) { $pr.title } else { $"($pr.title) @($pr.headRefName)" }),
        url: $pr.url
      }
    }
    let prefix = "\n          "
    let prs_joined = ($prs_cleaned | par-each -k {|pr| $"➜ ($pr.title) ($pr.url)" } | str join $prefix)
    let prs_string = (if (not ($prs_joined | is-empty)) { $"($prefix)($prs_joined)"} else { $prs_joined })

    {
      commit: $commit.0,
      message: $commit.1,
      prs: $prs_string
    }
  }
  let data_stringified = $data | par-each -k {|d|
    $"(ansi yellow)($d.commit)(ansi reset): (ansi green)($d.message)(ansi reset) (ansi magenta)($d.prs)(ansi reset)"
  } | str join "\n"

  print $data_stringified
}
