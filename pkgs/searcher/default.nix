{
  writeShellApplication,
  fzf,
  jq,
}:
writeShellApplication {
  name = "searcher";
  runtimeInputs = [
    fzf
    jq
  ];
  text = ''
    # Check if two or more arguments are provided
    if [ $# -ge 2 ]; then
      # First argument is the repo, the rest are search queries
      repo="$1"
      # Shift arguments so "$@" now represents the search queries
      shift
    else
      # Default to "nixpkgs" if less than two arguments are provided
      repo="nixpkgs"
    fi

    # Step 1: Run the nix search and prepare selection options with package names and keys
    options=$(nix search --json "$repo" "$@" | jq -r 'to_entries [ ] | "\(.value.pname) \(.key)"')

    # Step 2: Use fzf to let the user select a package, then generate and display its metadata
    selected=$(echo "$options" | fzf --ansi --preview-window=right:70%:wrap --preview="echo {2} | xargs -I {} nix eval --json ''${repo}#{}.meta | jq -C . " -d ' ')

    # Extract the package key from the selection for further processing if needed
    pkg_key=$(echo "$selected" | awk '{print $2}')

    # Step 3: Display metadata of the selected package
    if [ -n "$pkg_key" ]; then
      nix shell "nixpkgs#''${pkg_key}"
    else
      echo "No package selected."
    fi
  '';
}
