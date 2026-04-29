#!/usr/bin/env nu

# Splice a patched cli.js back into a Bun-compiled standalone binary.
#
# Layout of a `bun build --compile` Linux ELF binary:
#
#     [Bun runtime ELF ...]
#     [u64 payload_len]              <- appended right after the runtime
#     [payload = raw_bytes]:
#       [data: null-terminated names, contents, ...]
#       [module table: N x 52-byte CompiledModuleGraphFile entries]
#       [Offsets struct: 32 bytes]
#       [trailer: "\n---- Bun! ----\n" (16 bytes)]
#     [optional zero padding]
#
# Layout of a Mach-O Bun binary (macOS): same payload, but it lives inside
# a dedicated `__BUN` segment in the middle of the Mach-O image, with
# `__LINKEDIT` (containing the code signature) following it. To keep the
# Mach-O structurally valid for code-signing tools, we preserve the
# original file byte-for-byte and overwrite only the bytes within the
# `__BUN` region — the original payload was much larger than ours, so the
# tail of `__BUN` keeps original junk, which Bun never reads (it stops at
# payload_len). The Nix derivation re-signs the result with rcodesign.
#
# We drop the JSC bytecode cache, sourcemaps, module_info, and
# bytecode_origin_path — those are tied to the original source hash and
# would be invalid for a patched cli.js. Bun falls back to parsing source
# at load time when bytecode.length == 0.
#
# Usage:
#   splice.nu <original-binary> <patched-cli.js> <output-binary>

const TRAILER = 0x[0A 2D 2D 2D 2D 20 42 75 6E 21 20 2D 2D 2D 2D 0A] # "\n---- Bun! ----\n"
const OFFSETS_SIZE = 32
const MODULE_STRUCT_SIZE = 52

const MACHO_MAGIC_64 = 0xfeedfacf

# --- fixed-width integer read/pack helpers ---

def read-u8 [buf: binary, offset: int]: nothing -> int {
  $buf | bytes at $offset..<($offset + 1) | into int --endian little
}

def read-u32 [buf: binary, offset: int]: nothing -> int {
  $buf | bytes at $offset..<($offset + 4) | into int --endian little
}

def read-u64 [buf: binary, offset: int]: nothing -> int {
  $buf | bytes at $offset..<($offset + 8) | into int --endian little
}

def pack-u8 [val: int]: nothing -> binary {
  $val | into binary --endian little | bytes at 0..<1
}

def pack-u32 [val: int]: nothing -> binary {
  $val | into binary --endian little | bytes at 0..<4
}

def pack-u64 [val: int]: nothing -> binary {
  $val | into binary --endian little # defaults to 8 bytes
}

# --- parse helpers (operate on small pre-sliced blobs) ---

# Decode the 32-byte Offsets struct from its slice.
def parse-offsets-struct [blob: binary] {
  {
    byte_count: (read-u64 $blob 0)
    mod_off: (read-u32 $blob 8)
    mod_len: (read-u32 $blob 12)
    entry_id: (read-u32 $blob 16)
    flags: (read-u32 $blob 28)
  }
}

# Decode one 52-byte CompiledModuleGraphFile entry. `full` is the original
# binary (for content slicing); `raw_start` is where raw_bytes begins in it.
def parse-module-entry [entry: binary, full: binary, raw_start: int] {
  let name_off = read-u32 $entry 0
  let name_len = read-u32 $entry 4
  let cont_off = read-u32 $entry 8
  let cont_len = read-u32 $entry 12
  {
    name: ($full | bytes at ($raw_start + $name_off)..<($raw_start + $name_off + $name_len))
    content: ($full | bytes at ($raw_start + $cont_off)..<($raw_start + $cont_off + $cont_len))
    encoding: (read-u8 $entry 48)
    loader: (read-u8 $entry 49)
    fmt: (read-u8 $entry 50)
    side: (read-u8 $entry 51)
  }
}

# --- top-level parse / build ---

def parse-binary [binary: binary] {
  let trailer_pos = $binary | bytes index-of --end $TRAILER
  if $trailer_pos < 0 { error make { msg: "Bun trailer not found" } }

  # `bytes at` on a 236 MB binary re-walks the stream per call (~135 ms each).
  # Slice the two small metadata regions once, then parse from those.
  let offsets_blob = $binary | bytes at ($trailer_pos - $OFFSETS_SIZE)..<$trailer_pos
  let off = parse-offsets-struct $offsets_blob

  let trailer_len = $TRAILER | bytes length
  let raw_start = $trailer_pos + $trailer_len - ($off.byte_count + $OFFSETS_SIZE + $trailer_len)
  let mod_table_abs = $raw_start + $off.mod_off
  let mod_table_blob = $binary | bytes at $mod_table_abs..<($mod_table_abs + $off.mod_len)
  let num_modules = $off.mod_len // $MODULE_STRUCT_SIZE

  let modules = (0..($num_modules - 1) | each { |i|
    let entry = $mod_table_blob | bytes at ($i * $MODULE_STRUCT_SIZE)..<(($i + 1) * $MODULE_STRUCT_SIZE)
    parse-module-entry $entry $binary $raw_start
  })

  {
    raw_start: $raw_start
    modules: $modules
    entry_id: $off.entry_id
    flags: $off.flags
  }
}

# Build one 52-byte CompiledModuleGraphFile entry. We zero out sourcemap,
# bytecode, module_info, and bytecode_origin_path (dropped on round-trip).
def build-module-entry [m: record, name_off: int, cont_off: int]: nothing -> binary {
  [
    (pack-u32 $name_off)
    (pack-u32 ($m.name | bytes length))
    (pack-u32 $cont_off)
    (pack-u32 ($m.content | bytes length))
    (pack-u32 0) (pack-u32 0) # sourcemap
    (pack-u32 0) (pack-u32 0) # bytecode
    (pack-u32 0) (pack-u32 0) # module_info
    (pack-u32 0) (pack-u32 0) # bytecode_origin_path
    (pack-u8 $m.encoding)
    (pack-u8 $m.loader)
    (pack-u8 $m.fmt)
    (pack-u8 $m.side)
  ] | bytes collect
}

# Construct the new Bun payload (u64 payload_len followed by raw_bytes)
# that the runtime expects to find at __BUN.fileoff (Mach-O) or right
# after the ELF runtime (Linux).
def build-bun-payload [parsed: record, entry_content: binary]: nothing -> binary {
  let modules = ($parsed.modules | enumerate | each { |it|
    if $it.index == $parsed.entry_id {
      $it.item | upsert content $entry_content
    } else {
      $it.item
    }
  })

  # Each name and each content is null-terminated; stored-length excludes the null.
  # Compute cumulative offsets into raw_bytes purely functionally.
  let name_lens = ($modules | each { |m| ($m.name | bytes length) + 1 })
  let cont_lens = ($modules | each { |m| ($m.content | bytes length) + 1 })
  let name_offs = ($name_lens | reduce --fold [0] { |len, acc|
    $acc | append (($acc | last) + $len)
  })
  let names_total = ($name_offs | last)
  let cont_offs = ($cont_lens | reduce --fold [$names_total] { |len, acc|
    $acc | append (($acc | last) + $len)
  })
  let mod_table_off = ($cont_offs | last)

  let names_blob = ($modules | each { |m| $m.name | bytes add --end 0x[00] } | bytes collect)
  let contents_blob = ($modules | each { |m| $m.content | bytes add --end 0x[00] } | bytes collect)

  let mod_table = ($modules | enumerate | each { |it|
    build-module-entry $it.item ($name_offs | get $it.index) ($cont_offs | get $it.index)
  } | bytes collect)
  let mod_table_len = $mod_table | bytes length

  # byte_count excludes the Offsets struct and trailer that follow it.
  let byte_count = $mod_table_off + $mod_table_len + $OFFSETS_SIZE
  let offsets = [
    (pack-u64 $byte_count)
    (pack-u32 $mod_table_off)
    (pack-u32 $mod_table_len)
    (pack-u32 $parsed.entry_id)
    (pack-u32 0) # compile_exec_argv_ptr.offset
    (pack-u32 0) # compile_exec_argv_ptr.length
    (pack-u32 $parsed.flags)
  ] | bytes collect

  let raw = [$names_blob $contents_blob $mod_table $offsets $TRAILER] | bytes collect
  let payload_len = $raw | bytes length
  [(pack-u64 $payload_len) $raw] | bytes collect
}

def main [original: path, patched: path, output: path] {
  let binary = (open --raw $original | into binary)
  let patched_content = (open --raw $patched | into binary)
  let parsed = parse-binary $binary
  let entry = $parsed.modules | get $parsed.entry_id
  let orig_len = $entry.content | bytes length
  let patch_len = $patched_content | bytes length
  print $"Replacing entry module #($parsed.entry_id) \(($entry.name | decode utf-8)\): ($orig_len) -> ($patch_len) bytes"

  let bun_payload = build-bun-payload $parsed $patched_content
  let bun_fileoff = $parsed.raw_start - 8

  if (read-u32 $binary 0) == $MACHO_MAGIC_64 {
    # Mach-O: copy original verbatim, then patch the __BUN region in place.
    # All segment offsets — including __LINKEDIT and the original (now
    # invalid) code signature — stay at the same byte positions, so the
    # Mach-O remains structurally valid and rcodesign can replace the
    # signature in the Nix derivation. Bytes after `bun_payload` inside
    # __BUN keep the original junk; Bun stops at payload_len at runtime.
    cp $original $output
    chmod u+w $output
    let tmp = $"($output).bun-payload"
    $bun_payload | save -f $tmp
    if ($bun_fileoff mod 4096) != 0 {
      error make { msg: $"__BUN fileoff not 4K-aligned: ($bun_fileoff)" }
    }
    ^dd if=$tmp of=$output bs=4096 seek=($bun_fileoff // 4096) conv=notrunc err>| ignore
    rm $tmp
    let final_size = (ls $output | get 0.size | into int)
    print $"Patched __BUN at offset ($bun_fileoff); file size unchanged \(($final_size) bytes\)"
  } else {
    # ELF (Linux): original truncate-and-append behavior.
    let runtime = $binary | bytes at 0..<$bun_fileoff
    let spliced = [$runtime $bun_payload] | bytes collect
    $spliced | save -f $output
    print $"Wrote (($spliced | bytes length)) bytes to ($output)"
  }
}
