{ lib, pkgs, ... }:
let
  pueueDaemon = lib.getExe' pkgs.pueue "pueued";
in
# formatYAML = lib.generators.toYAML { };
{
  config = {
    home.packages = [
      pkgs.pueue
    ];

    # TODO: remove after testing on mac

    # home.file.".config/pueue/pueue.yml".text = formatYAML {
    #   shared = {
    #     pueue_directory = "~/.local/share/pueue";
    #     use_unix_socket = true;
    #     runtime_directory = null;
    #     unix_socket_path = "~/.local/share/pueue/pueue_your_user.socket";
    #     host = "localhost";
    #     port = 6924;
    #     daemon_cert = "~/.local/share/pueue/certs/daemon.cert";
    #     daemon_key = "~/.local/share/pueue/certs/daemon.key";
    #     shared_secret_path = "~/.local/share/pueue/shared_secret";
    #   };
    #
    #   client = {
    #     restart_in_place = false;
    #     read_local_logs = true;
    #     show_confirmation_questions = false;
    #     show_expanded_aliases = false;
    #     dark_mode = false;
    #     max_status_height = null;
    #     status_time_format = "%H:%M:%S";
    #     status_datetime_format = "%Y-%m-%d\n%H:%M:%S";
    #   };
    #
    #   daemon = {
    #     default_parallel_tasks = 1;
    #     pause_group_on_failure = false;
    #     pause_all_on_failure = false;
    #     callback = "\"Task {{ id }}\nCommand: {{ command }}\nPath: {{ path }}\nFinished with status '{{ result }}'\"";
    #     callback_log_lines = 10;
    #     groups = {
    #       default = 1;
    #     };
    #   };
    # };

    services.pueue = {
      enable = pkgs.stdenv.isLinux;
    };

    launchd.agents.pueueDaemon = {
      enable = pkgs.stdenv.isDarwin;
      config = {
        Debug = true;
        Program = pueueDaemon;
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "/tmp/pueueDaemon.log";
        StandardErrorPath = "/tmp/pueueDaemon.err";
      };
    };
  };
}
