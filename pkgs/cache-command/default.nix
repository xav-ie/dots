{ writeShellApplication, }:
writeShellApplication {
  name = "cache-command";
  text = ''
    # Create a hash of the entire command line to use as a cache file name
    cmd_hash=$(echo "$*" | md5sum | cut -d' ' -f1)
    cache_dir="$HOME/.cache/cmd_cache"
    cache_file="''${cache_dir}/''${cmd_hash}"

    mkdir -p "''${cache_dir}"

    # Determine if the cache file exists and is less than an hour old
    update_cache=1
    if [ -f "''${cache_file}" ]; then
        current_time=$(date +%s)
        last_modified=$(date -r "''${cache_file}" +%s)
        if [ $((current_time - last_modified)) -lt 3600 ]; then
            update_cache=0
        fi
    fi

    # Execute the command and cache its output if necessary
    if [ "''${update_cache}" -eq 1 ]; then
        "$@" > "''${cache_file}"
    fi

    # Display the cached output
    cat "''${cache_file}"
  '';
}
