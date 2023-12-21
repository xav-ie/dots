#!/usr/bin/env sh

TOKEN_DIR="$HOME/.config/tokens"

echo "Checking directory: $TOKEN_DIR"

# Check if the directory exists
if [ -d "$TOKEN_DIR" ]; then
    echo "Directory exists!"
    # Loop through each file in the directory
    for token_file in "$TOKEN_DIR"/*; do
        echo "Processing file: $token_file"
        # If it's a regular file
        if [ -f "$token_file" ]; then
            # Get the filename without the directory part
            token_name=$(basename "$token_file")
            # Export the environment variable
            export "${token_name}"=$(cat "$token_file")
            echo "Set ${token_name} to $(cat "$token_file")"
        fi
    done
else
    echo "Directory does not exist!"
fi
