#!/usr/bin/env nu

def get_podman_pids [] {
  let container_root_pids = (ps --long
    | where command =~ "conmon" or command =~ "podman"
    | get pid
  )
  mut all_podman_pids = $container_root_pids
  for root_pid in $container_root_pids {
    try {
      let descendants = (^pstree -p $root_pid | parse -r '\((\d+)\)' | get capture0 | into int)
      $all_podman_pids = ($all_podman_pids | append $descendants)
    } catch {
    }
  }
  let all_processes = (ps --long | select pid ppid)
  mut additional_pids = []
  for container_pid in $container_root_pids {
    let descendants = (get_all_descendants $all_processes $container_pid)
    $additional_pids = ($additional_pids | append $descendants)
  }
  $all_podman_pids = ($all_podman_pids | append $additional_pids)
  $all_podman_pids | uniq | sort
}

def get_all_descendants [processes: table, parent_pid: int] {
  let children = ($processes | where ppid == $parent_pid | get pid)
  mut all_descendants = $children
  for child_pid in $children {
    let grandchildren = (get_all_descendants $processes $child_pid)
    $all_descendants = ($all_descendants | append $grandchildren)
  }
  $all_descendants
}

# pgrep but with podman processes filtered out
# to get "podman" processes, simply call with "podman"
def main [filter?: string] {
  let all_processes = (ps --long)

  match $filter {
    null => { $all_processes },
    "podman" => {
      let podman_pids = (get_podman_pids)
      $all_processes | where pid in $podman_pids
    },
    _ => {
      let podman_pids = (get_podman_pids)
      $all_processes | where pid not-in $podman_pids | where command =~ $filter
    }
  }
}
