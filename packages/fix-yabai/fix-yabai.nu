try { sudo yabai --load-sa };

yabai -m query --windows
| jq '.[].id'
| lines
| each { |line|
    try { yabai -m window $line --sub-layer normal }
  }
