#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/uio.h>
#include <sys/un.h>
#include <unistd.h>

#define MAX_PATH 4096

// Find git root by walking up directories looking for .git
// Returns 1 if found, 0 if not. Fills git_root with the git root path.
int find_git_root(const char *start_dir, char *git_root) {
  char path_buf[MAX_PATH + 6]; // +6 for "/.git" + null
  struct stat st;

  // Copy start_dir into path_buf
  size_t len = strlen(start_dir);
  if (len >= MAX_PATH)
    return 0;
  memcpy(path_buf, start_dir, len + 1);

  while (1) {
    // Append "/.git" to current path (in-place, no snprintf!)
    memcpy(path_buf + len, "/.git", 6); // includes null terminator

    if (stat(path_buf, &st) == 0) {
      // Found it! Copy path without "/.git" suffix
      memcpy(git_root, path_buf, len);
      git_root[len] = '\0';
      return 1;
    }

    // Remove "/.git" suffix
    path_buf[len] = '\0';

    // Find last '/' to go up one directory (manual dirname)
    if (len == 0 || len == 1)
      return 0; // At root

    char *last_slash = path_buf + len - 1;
    while (last_slash > path_buf && *last_slash != '/') {
      last_slash--;
    }

    // If we're at the beginning or root, we're done
    if (last_slash == path_buf) {
      return 0; // At root directory
    }

    // Truncate at the slash
    *last_slash = '\0';
    len = last_slash - path_buf;
  }
}

int main() {
  // Only run if we're in tmux
  char *tmux_pane = getenv("TMUX_PANE");
  if (!tmux_pane || tmux_pane[0] == '\0') {
    return 0;
  }

  // Prefer invoked-with pane id, otherwise use current pane id
  char *pane_id = getenv("TMUX_TAB_UPDATE_PANE");
  if (!pane_id || pane_id[0] == '\0') {
    pane_id = tmux_pane;
  }

  char *pane_dir = getenv("PWD");
  if (!pane_dir) {
    return 1;
  }

  // Find git root and calculate prefix using directory walking
  char git_root[MAX_PATH];
  char git_prefix[MAX_PATH] = "";

  if (find_git_root(pane_dir, git_root)) {
    // Calculate relative path from git_root to pane_dir
    size_t root_len = strlen(git_root);
    size_t dir_len = strlen(pane_dir);

    if (dir_len > root_len && pane_dir[root_len] == '/') {
      // pane_dir is inside git_root
      strncpy(git_prefix, pane_dir + root_len + 1, MAX_PATH - 1);
      git_prefix[MAX_PATH - 1] = '\0';
    }
    // else: pane_dir == git_root, so git_prefix stays empty
  }

  char tab_name_buf[MAX_PATH];
  char *tab_name;

  // Check if we're in HOME
  char *home = getenv("HOME");
  if (home && strcmp(pane_dir, home) == 0) {
    tab_name = "~";
  } else {
    // Match the bash script logic exactly
    size_t pane_dir_len = strlen(pane_dir);
    size_t git_prefix_len = strlen(git_prefix);
    int binary_git_prefix = (git_prefix_len != 0) ? 1 : 0;

    // keep_len = pane_dir_len - git_prefix_len - binary_git_prefix
    size_t keep_len = pane_dir_len - git_prefix_len - binary_git_prefix;

    // Get basename manually by finding last '/' in pane_dir[0:keep_len]
    const char *base_ptr = pane_dir;
    for (size_t i = 0; i < keep_len; i++) {
      if (pane_dir[i] == '/') {
        base_ptr = pane_dir + i + 1;
      }
    }

    // Calculate basename length
    size_t base_len = keep_len - (base_ptr - pane_dir);

    // Copy basename to trimmed_base
    char trimmed_base[MAX_PATH];
    memcpy(trimmed_base, base_ptr, base_len);
    trimmed_base[base_len] = '\0';

    // Build tab_name_raw = trimmed_base + "/" + git_prefix
    char tab_name_raw[MAX_PATH];
    snprintf(tab_name_raw, sizeof(tab_name_raw), "%s/%s", trimmed_base,
             git_prefix);

    // Calculate final_index
    size_t trimmed_base_len = strlen(trimmed_base);
    size_t final_index =
        trimmed_base_len + git_prefix_len + binary_git_prefix - 1;

    // Substring tab_name_raw[0:final_index+1]
    strncpy(tab_name_buf, tab_name_raw, final_index + 1);
    tab_name_buf[final_index + 1] = '\0';
    tab_name = tab_name_buf;
  }

  // Connect directly to tmux socket instead of spawning process
  char *tmux_env = getenv("TMUX");
  if (!tmux_env)
    return 0;

  // TMUX env format: /path/to/socket,pid,session_id
  char socket_path[MAX_PATH];
  char *comma = strchr(tmux_env, ',');
  if (!comma)
    return 0;

  size_t path_len = comma - tmux_env;
  strncpy(socket_path, tmux_env, path_len);
  socket_path[path_len] = '\0';

  // Create and connect socket
  int sock = socket(AF_UNIX, SOCK_STREAM, 0);
  if (sock < 0)
    return 0;

  struct sockaddr_un addr;
  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  strncpy(addr.sun_path, socket_path, sizeof(addr.sun_path) - 1);

  if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
    close(sock);
    return 0;
  }

  // Build all messages in buffers, then send with single sendmsg
  char msg1[64], msg2[64], msg3[32], msg4[16], msg5[MAX_PATH];
  char *p;
  pid_t pid = getpid();
  size_t len1, len2, len3, len4, len5;

  // Build MSG_IDENTIFY_TERM
  p = msg1;
  *(uint32_t *)p = 101;
  p += 4;
  *(uint32_t *)p = 0;
  p += 4; // length placeholder
  *(uint32_t *)p = 8;
  p += 4;
  *(uint32_t *)p = (uint32_t)pid;
  p += 4;
  memcpy(p, "screen", 7);
  p += 7; // "screen" + null = 7 bytes
  len1 = p - msg1;
  *(uint32_t *)(msg1 + 4) = len1;

  // Build MSG_IDENTIFY_TTYNAME
  p = msg2;
  *(uint32_t *)p = 102;
  p += 4;
  *(uint32_t *)p = 0;
  p += 4; // length placeholder
  *(uint32_t *)p = 8;
  p += 4;
  *(uint32_t *)p = (uint32_t)pid;
  p += 4;
  *p = '\0';
  p += 1; // Empty string, just null terminator
  len2 = p - msg2;
  *(uint32_t *)(msg2 + 4) = len2;

  // Build MSG_IDENTIFY_CLIENTPID
  p = msg3;
  *(uint32_t *)p = 107;
  p += 4;
  *(uint32_t *)p = 16 + sizeof(pid_t);
  p += 4;
  *(uint32_t *)p = 8;
  p += 4;
  *(uint32_t *)p = (uint32_t)pid;
  p += 4;
  memcpy(p, &pid, sizeof(pid_t));
  p += sizeof(pid_t);
  len3 = p - msg3;

  // Build MSG_IDENTIFY_DONE
  p = msg4;
  *(uint32_t *)p = 106;
  p += 4;
  *(uint32_t *)p = 16;
  p += 4;
  *(uint32_t *)p = 8;
  p += 4;
  *(uint32_t *)p = (uint32_t)pid;
  p += 4;
  len4 = 16;

  // Build MSG_COMMAND
  p = msg5;
  *(uint32_t *)p = 200;
  p += 4;
  *(uint32_t *)p = 0;
  p += 4; // length placeholder
  *(uint32_t *)p = 8;
  p += 4;
  *(uint32_t *)p = (uint32_t)pid;
  p += 4;
  int argc = 4;
  memcpy(p, &argc, sizeof(int));
  p += sizeof(int);
  memcpy(p, "rename-window", 14);
  p += 14; // "rename-window" + null = 14
  memcpy(p, "-t", 3);
  p += 3; // "-t" + null = 3
  // For pane_id and tab_name, we still need strlen since they're dynamic
  size_t pane_id_len = strlen(pane_id) + 1;
  memcpy(p, pane_id, pane_id_len);
  p += pane_id_len;
  size_t tab_name_len = strlen(tab_name) + 1;
  memcpy(p, tab_name, tab_name_len);
  p += tab_name_len;
  len5 = p - msg5;
  *(uint32_t *)(msg5 + 4) = len5;

  // Send all messages in a single sendmsg call
  struct iovec iov[5];
  iov[0].iov_base = msg1;
  iov[0].iov_len = len1;
  iov[1].iov_base = msg2;
  iov[1].iov_len = len2;
  iov[2].iov_base = msg3;
  iov[2].iov_len = len3;
  iov[3].iov_base = msg4;
  iov[3].iov_len = len4;
  iov[4].iov_base = msg5;
  iov[4].iov_len = len5;

  struct msghdr msghdr = {0};
  msghdr.msg_iov = iov;
  msghdr.msg_iovlen = 5;
  sendmsg(sock, &msghdr, 0);

  // Close socket immediately - server will process the command asynchronously
  close(sock);

  return 0;
}
