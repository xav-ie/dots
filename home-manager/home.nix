{ inputs, lib, config, pkgs, ... }: 
let merge = lib.foldr (a: b: a // b) { };
in {
  # You can import other home-manager modules here
  imports = [
    # If you want to use home-manager modules from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModule

    # You can also split up your configuration and import pieces of it here:
    # ./nvim.nix
  ];

  # nixpkgs = {
  #   # You can add overlays here
  #   overlays = [
  #     # If you want to use overlays exported from other flakes:
  #     # neovim-nightly-overlay.overlays.default
  #
  #     # Or define it inline, for example:
  #     # (final: prev: {
  #     #   hi = final.hello.overrideAttrs (oldAttrs: {
  #     #     patches = [ ./change-hello-to-hi.patch ];
  #     #   });
  #     # })
  #   ];
  #   # Configure your nixpkgs instance
  #   config = {
  #     # Disable if you don't want unfree packages
  #     allowUnfree = true;
  #     # Workaround for https://github.com/nix-community/home-manager/issues/2942
  #     allowUnfreePredicate = (_: true);
  #   };
  # };

  # TODO: Set your username
  home = {
    username = "x";
    homeDirectory = "/home/x";
  };

  # Add stuff for your user as you see fit:
  # programs.neovim.enable = true;
  # home.packages = with pkgs; [ steam ];

  # Enable home-manager and git
  programs = {
    home-manager = {
      enable = true;
      # useGlobalPkgs = true;

    };
    git = {
      enable = true;
      userName = "xav-ie";
      userEmail = "xruizify@gmail.com";
      aliases = {
        graph = "log --graph --pretty=tformat:'%C(bold blue)%h%Creset %s %C(bold green)%d%Creset %C(blue)<%an>%Creset %C(dim cyan)%cr' --abbrev-commit --decorate";
      };
      extraConfig = {
        core = {
          pager = "delta";
        };
        interactive = {
          diffFilter = "delta --color-only";
        };
        delta = {
          navigate = true;
          line-numbers = true;
          true-color =  "always";
        };
        merge = {
          conflictstyle = "diff3";
        };
        diff = {
          colorMoved = "default";
        };
      };
    };
    zsh = {
      enable = true;
      enableAutosuggestions = true;
      enableCompletion = true;
    };
    firefox = {
      enable = true;
      

      profiles.x = {
        id = 0;
        isDefault = true;
        settings = merge [
          (import ./programs/firefox/annoyances.nix)
          (import ./programs/firefox/settings.nix)

        ];
        userChrome = ''
          /* hides the native tabs */
          #TabsToolbar {
            visibility: collapse;
          }
          #titlebar {
            visibility: collapse;
          }
          #sidebar-header {
            visibility: collapse !important;
          } 
          '';
        extensions = with pkgs.nur.repos.rycee.firefox-addons; [
          bitwarden
          ublock-origin
          vimium-c
          sidebartabs
          newtab-adapter
          videospeed

        ];

      };
    };
  };

  gtk = {
    enable = true;
    theme.name = "adw-gtk3";
    cursorTheme.name = "Bibata-Modern-Ice";
    iconTheme.name = "GruvboxPlus";
  };


  xdg.mimeApps.defaultApplications = {
    "text/plain" = [ "neovide.desktop" ];
    "application/pdf" = [ "zathura.desktop" ];
    "image/*" = [ "sxiv.desktop" ];
    "video/*" = [ "mpv.desktop" ];
    "text/html" = [ "firefox.desktop" ];
    "x-scheme-handler/http" = [ "firefox.desktop" ];
    "x-scheme-handler/https" = [ "firefox.desktop" ];
    "x-scheme-handler/ftp" = [ "firefox.desktop" ];
    "application/xhtml+xml" = [ "firefox.desktop" ];
    "application/xml" = [ "firefox.desktop" ]; 
  };
  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";


  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.05";
  home.sessionVariables = {
    EDITOR = "vim";
  };
}


