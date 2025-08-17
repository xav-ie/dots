# https://discord.com/channels/601130461678272522/615253963645911060/1369010752475631718 by Bahex
@search-terms blocking timeout
export def with-timeout [timeout: duration, task: closure] {
    let input = $in
    let parent_id = job id
    let task_id = job spawn {
        $input | do $task | job send --tag (job id) $parent_id
    }
    try {
        job recv --tag $task_id --timeout $timeout
    } catch {
        # be sure to try killing the zenity window if running
        try { job kill $task_id }
        error make -u { msg: "Password GUI ask timed out." }
    }
}

def main [prompt?: string] {
  let title = match $prompt {
    null | "" => "Authentication Required",
    _ => $prompt
  }
  with-timeout 30sec {||
    let result = (^zenity --password --title=$"($title)" err> /dev/null)

    print $result
  }
}
