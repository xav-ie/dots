{
  writeCBin,
  atuin,
  pkgs-bleeding,
}:
# tmux's `default-shell` setting takes a binary path with no arguments.
# This tiny C shim execs `atuin hex --shell <nu>`.  Going via C instead
# of bash saves ~2 ms per pane open (bash startup from /nix/store costs
# ~2 ms; this shim is ~0.3 ms because libSystem is in darwin's dyld
# shared cache).
writeCBin "tmux-shell" ''
  #include <stdio.h>
  #include <unistd.h>

  int main(int argc, char **argv) {
      char *new_argv[argc + 4];
      new_argv[0] = "atuin";
      new_argv[1] = "hex";
      new_argv[2] = "--shell";
      new_argv[3] = "${pkgs-bleeding.nushell}/bin/nu";
      for (int i = 1; i < argc; i++) {
          new_argv[i + 3] = argv[i];
      }
      new_argv[argc + 3] = (char *)0;
      execv("${atuin}/bin/atuin", new_argv);
      perror("tmux-shell: execv atuin");
      return 127;
  }
''
