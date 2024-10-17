{ inputs, pkgs, ... }:
{
  imports = [
    ../programs/sketchybar
  ];

  nixpkgs = {
    overlays = [
      inputs.brew-nix.overlays.default
    ];
  };

  home = {
    packages = with pkgs; [
      brewCasks.bitwarden
      (brewCasks.chromium.overrideAttrs (oldAttrs: {
        src = pkgs.fetchurl {
          url = builtins.head oldAttrs.src.urls;
          hash = "sha256-zZHAB7TozshPfoVRfAllYFl4kXrXAok2KqHPa3gSu/c=";
        };
      }))
      brewCasks.firefox
      brewCasks.protonvpn
      brewCasks.microsoft-edge
      brewCasks.raycast
      brewCasks.slack
      # for sketchybar
      brewCasks.sf-symbols

      # to install MAS (Mac App-Store) apps
      mas
      zoom-us
    ];

    # 1. what is currently installed?
    # ❯ mas list | awk '{print $1}'
    # 682658836
    # 408981434
    # 1501592214 # twingate
    # 409201541
    # 409183694
    # 6446206067 # klack
    # 409203825
    #
    # 2. By tacking on the mas apps that should be installed, we can filter with
    # `uniq -u` and get the ones that should *not* be installed like this:
    # ❯ (mas list | awk '{print $1}'; \
    #    echo -e "6446206067\n1501592214") | sort | uniq -u
    # 408981434
    # 409183694
    # 409201541
    # 409203825
    # 682658836
    #
    # 3. a. `sudo mas uninstall` each id
    # ❯ (mas list | awk '{print $1}'; \
    #    echo -e "6446206067\n1501592214") | sort | uniq -u \
    #   | xargs -I {} sudo mas uninstall {}
    # Error: Not installed # x5
    # whoops! https://github.com/mas-cli/mas/issues/313
    # `mas` should be able to uninstall but it looks like there is some intricate
    # permissions issues
    #
    # 3. b. workaround using manual method
    # Get the bundleId of each of the applications to uninstall
    # ❯ (mas list | awk '{print $1}'; \
    #    echo -e "6446206067\n1501592214") | sort | uniq -u \
    #   | xargs -I {}  curl -s -X GET "https://itunes.apple.com/lookup?id={}" \
    #   | jq -r '.results[0].bundleId'
    # com.apple.iMovieApp
    # com.apple.iWork.Keynote
    # com.apple.iWork.Pages
    # com.apple.iWork.Numbers
    # com.apple.garageband10
    #
    # 4. Use these bundleIds returns to look up their location on the computer
    # ❯ (mas list | awk '{print $1}'; \
    #    echo -e "6446206067\n1501592214") | sort | uniq -u \
    #   | xargs -I {}  curl -s -X GET "https://itunes.apple.com/lookup?id={}" \
    #   | jq -r '.results[0].bundleId' \
    #   | xargs -I {} mdfind "kMDItemCFBundleIdentifier == '{}'"
    # /Applications/iMovie.app
    # /Applications/Keynote.app
    # /Applications/Pages.app
    # /Applications/Numbers.app
    # /Applications/GarageBand.app
    # ^ the benefit of using `mdfind` is that is sidesteps the issue in `mas`
    # as it only searches locations available to the current user. This means,
    # as long as permissions are set up correctly so that *you* cannot see
    # another user's home directory, then their `~/Applications/` will never
    # show up here! We could also apply filtering here to be extra safe, but
    # uncessary. Especially so since I don't plan on having multiple users ever.
    # Oooooof. But if you have a Cask installed with `brew`, that would also show
    # up in this list. I don't use `brew`, but you would need to somehow query
    # its install locations and exclude those from this list, since those could
    # not have been made by mas.
    #
    # 5. uninstall 🎉
    # ❯ (mas list | awk '{print $1}'; \
    #    echo -e "6446206067\n1501592214") | sort | uniq -u \
    #   | xargs -I {}  curl -s -X GET "https://itunes.apple.com/lookup?id={}" \
    #   | jq -r '.results[0].bundleId' \
    #   | xargs -I {} mdfind "kMDItemCFBundleIdentifier == '{}'" \
    #   | xargs -I {} sudo rm -rf {}
    #
    # 6. Bonus: use GNU Parallel to increase uninstall speed
    # having to download each, then parse each, then remove each sequentially
    # is slow and unnecessary. Using GNU Parallel, we can greatly increase the
    # speed of this to be nearly instantaneous.
    #
    # ❯ (mas list | awk '{print $1}'; \
    #    echo -e "6446206067\n1501592214" ) | sort | uniq -u \
    #   | parallel -j $(nproc) '
    #   # Fetch the bundleId using iTunes API
    #   bundleId=$(curl -s -X GET "https://itunes.apple.com/lookup?id={}" \
    #            | jq -r ".results[0].bundleId");
    #
    #   # Find the application path using mdfind
    #   appPath=$(mdfind "kMDItemCFBundleIdentifier == \"$bundleId\"");
    #
    #   # Uninstall the app if found
    #   if [ -n "$appPath" ]; then
    #     echo "Uninstalling $appPath...";
    #     sudo rm -rf "$appPath";
    #
    #     # Optionally clean up support files
    #     sudo rm -rf ~/Library/Preferences/"$bundleId".plist;
    #     sudo rm -rf ~/Library/Caches/"$bundleId";
    #     sudo rm -rf ~/Library/Application\ Support/"$bundleId";
    #   else
    #     echo "App not found for ID {}";
    #   fi
    # '
    #
    # # Apps to install/keep:
    # 6446206067 # klack
    # 1501592214 # twingate
    # 497799835 # xcode
    # TODO: how to run the above script on every system rebuild?

    stateVersion = "23.11";
    sessionVariables = { };
  };
}
