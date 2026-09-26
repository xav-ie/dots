#!/usr/bin/env nu

# Splice patched JS modules back into a Bun-compiled standalone binary.
#
# A `bun build --compile` binary ends with:
#
#     [u64 payload_len][raw_bytes][optional padding]
#     raw_bytes = [data blobs][module table: N x 52 bytes][Offsets: 32 bytes][trailer]
#
# Each module entry holds StringPointer {offset,length} pairs into the data
# blobs for name, content, sourcemap, JSC bytecode, module_info and
# bytecode_origin_path. Offsets are relative to the start of raw_bytes.
#
# Rebuilding the payload from scratch does not survive Bun 1.4 (it panics
# unless per-module module_info and blob alignment are reproduced exactly),
# so instead the file is edited in place: a patched module's source is
# written over its now-stale bytecode blob, which is always several times
# larger than the source it was compiled from. Everything else — offsets,
# alignment, every other module's bytecode — stays byte-identical, and the
# file size never changes, so Mach-O segments stay valid too (the Nix
# derivation re-signs, since the edited bytes are inside the signed region).
#
# Only the patched module loses its bytecode cache and gets re-parsed at
# launch; the rest of the CLI still starts from cache.
#
# `bytes at` copies its whole input, which is ~80 ms on a 237 MB binary, so
# the binary is sliced only a few times and everything else reads the slices.
#
# Usage:
#   splice.nu <original-binary> <extracted-dir> <output-binary> <module-name>...

const TRAILER = 0x[0A 2D 2D 2D 2D 20 42 75 6E 21 20 2D 2D 2D 2D 0A] # "\n---- Bun! ----\n"
const OFFSETS_SIZE = 32
const MODULE_STRUCT_SIZE = 52

def u32 [buf: binary, offset: int]: nothing -> int {
  $buf | bytes at $offset..<($offset + 4) | into int --endian little
}

def pack-u32 [val: int]: nothing -> binary {
  $val | into binary --endian little | bytes at 0..<4
}

# Overwrite `data` at byte `offset` of `file` without truncating it.
def write-at [file: path, offset: int, data: binary] {
  $data | ^dd $"of=($file)" bs=1M $"seek=($offset)" oflag=seek_bytes conv=notrunc status=none
}

def main [
  original: path
  extracted: path
  output: path
  ...names: string
] {
  if ($names | is-empty) {
    error make {msg: "Usage: splice.nu <original> <extracted-dir> <output> <module>..."}
  }

  let buf = open --raw $original | into binary
  let trailer_pos = $buf | bytes index-of --end $TRAILER
  if $trailer_pos < 0 { error make {msg: "Bun trailer not found"} }

  let offsets = $buf | bytes at ($trailer_pos - $OFFSETS_SIZE)..<$trailer_pos
  let byte_count = $offsets | bytes at 0..<8 | into int --endian little
  let mod_off = u32 $offsets 8
  let mod_len = u32 $offsets 12
  let raw_start = $trailer_pos - $byte_count - $OFFSETS_SIZE
  let table_start = $raw_start + $mod_off
  let table = $buf | bytes at $table_start..<($table_start + $mod_len)

  let entries = 0..<($mod_len // $MODULE_STRUCT_SIZE) | each {|i|
    let e = $table | bytes at ($i * $MODULE_STRUCT_SIZE)..<(($i + 1) * $MODULE_STRUCT_SIZE)
    {
      index: $i
      name_off: (u32 $e 0)
      name_len: (u32 $e 4)
      content_off: (u32 $e 8)
      content_len: (u32 $e 12)
      bytecode_off: (u32 $e 24)
      bytecode_len: (u32 $e 28)
    }
  }

  # Names sit together in one small region; slice it once and decode from it.
  let names_lo = $entries | get name_off | math min
  let names_hi = $entries | each {|e| $e.name_off + $e.name_len } | math max
  let names_blob = $buf | bytes at ($raw_start + $names_lo)..<($raw_start + $names_hi)
  let entries = $entries | each {|e|
    let off = $e.name_off - $names_lo
    let name = $names_blob | bytes at $off..<($off + $e.name_len) | decode utf-8
    $e | insert name ($name | split row "/" | last)
  }

  cp $original $output
  chmod u+w $output

  for name in $names {
    let matches = $entries | where name == $name
    if ($matches | is-empty) { error make {msg: $"no module named ($name) in the Bun payload"} }
    let e = $matches | last

    # Content is null-terminated, so the slot needs one byte more than the source.
    let patched = open --raw ($extracted | path join $name) | into binary
    let len = $patched | bytes length
    let slot = if $len < $e.bytecode_len {
      {off: $e.bytecode_off, kind: bytecode}
    } else if $len < $e.content_len {
      {off: $e.content_off, kind: content}
    } else {
      error make {msg: $"no room for ($name): ($len) bytes does not fit the bytecode \(($e.bytecode_len)\) or content \(($e.content_len)\) slot"}
    }

    (write-at
      $output
      ($raw_start + $slot.off)
      ($patched | bytes add --end 0x[00])
    )
    let entry_pos = $table_start + $e.index * $MODULE_STRUCT_SIZE
    (write-at
      $output
      ($entry_pos + 8)
      ([
        (pack-u32 $slot.off)
        (pack-u32 $len)
      ] | bytes collect)
    )
    write-at $output ($entry_pos + 24) (0 | into binary) # bytecode offset + length

    print $"Spliced ($name): ($e.content_len) -> ($len) bytes \(into the ($slot.kind) slot\)"
  }
}
