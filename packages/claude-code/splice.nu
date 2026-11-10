#!/usr/bin/env nu

# Splice patched JS modules back into a Bun-compiled standalone binary.
#
# A `bun build --compile` binary carries its payload in a section that ends
# its segment (Mach-O `__BUN,__bun`, ELF `.bun` in the last PT_LOAD):
#
#     [u64 payload_len][raw_bytes][zero padding to the end of the segment]
#     raw_bytes = [data blobs][module table: N x 52 bytes][Offsets: 32 bytes][trailer]
#
# Each module entry holds StringPointer {offset,length} pairs into the data
# blobs for name, content, sourcemap, JSC bytecode, module_info and
# bytecode_origin_path. Offsets are relative to the start of raw_bytes, and
# Offsets.byte_count covers everything before the Offsets struct.
#
# Rebuilding the payload from scratch does not survive Bun 1.4 (it panics
# unless per-module module_info and blob alignment are reproduced exactly),
# and bytecode may be one blob shared by every module, so no existing bytes
# can be reused either. Instead each patched source is appended after the
# existing blobs, its module entry is pointed at it with the bytecode cleared,
# and Offsets + trailer move to the new end. Every other byte of the payload
# stays put. When the payload outgrows its segment's padding, everything after
# the segment (Mach-O `__LINKEDIT`, ELF non-alloc sections and section headers)
# shifts by a page-aligned delta and the headers pointing at it are updated.
# On Mach-O the Nix derivation re-signs, which rewrites the code signature.
#
# Only patched modules lose their bytecode cache and get re-parsed at launch;
# the rest of the CLI still starts from cache.
#
# `bytes at` copies its whole input, which is ~80 ms on a 300 MB binary, so
# the binary is sliced only a few times and everything else reads the slices.
#
# Usage:
#   splice.nu <original-binary> <extracted-dir> <output-binary> <module-name>...

const TRAILER = 0x[0A 2D 2D 2D 2D 20 42 75 6E 21 20 2D 2D 2D 2D 0A] # "\n---- Bun! ----\n"
const HEADER_SIZE = 8
const OFFSETS_SIZE = 32
const MODULE_STRUCT_SIZE = 52
const PAGE_SIZE = 0x10000

def u32 [buf: binary, offset: int]: nothing -> int {
  $buf | bytes at $offset..<($offset + 4) | into int --endian little
}

def u64 [buf: binary, offset: int]: nothing -> int {
  $buf | bytes at $offset..<($offset + 8) | into int --endian little
}

def pack-u32 [val: int]: nothing -> binary {
  $val | into binary --endian little | bytes at 0..<4
}

def pack-u64 [val: int]: nothing -> binary {
  $val | into binary --endian little | bytes at 0..<8
}

# Overwrite `data` at byte `offset` of `file` without truncating it.
def write-at [file: path, offset: int, data: binary] {
  $data | ^dd $"of=($file)" bs=1M $"seek=($offset)" oflag=seek_bytes conv=notrunc status=none
}

# Shift a u32 file offset at `pos` of `buf` (written to `file` at `base + pos`)
# when it points at or past `boundary`.
def shift-u32 [file: path, buf: binary, base: int, pos: int, boundary: int, delta: int] {
  let v = u32 $buf $pos
  if $v >= $boundary { write-at $file ($base + $pos) (pack-u32 ($v + $delta)) }
}

# Mach-O 64: the payload's segment is followed only by `__LINKEDIT`, whose
# contents are addressed by file offsets in the load commands.
def macho-layout [buf: binary, section_off: int]: nothing -> record {
  let ncmds = u32 $buf 16
  mut pos = 32
  mut seg = -1
  mut sect = -1
  for _ in 0..<$ncmds {
    if (u32 $buf $pos) == 0x19 {
      let nsects = u32 $buf ($pos + 64)
      for s in 0..<$nsects {
        let sp = $pos + 72 + $s * 80
        if (u32 $buf ($sp + 48)) == $section_off {
          $seg = $pos
          $sect = $sp
        }
      }
    }
    $pos += u32 $buf ($pos + 4)
  }
  if $seg < 0 { error make {msg: "no Mach-O section holds the Bun payload"} }
  {seg: $seg, sect: $sect, end: ((u64 $buf ($seg + 40)) + (u64 $buf ($seg + 48)))}
}

def macho-grow [file: path, head: binary, layout: record, size: int, boundary: int, delta: int] {
  write-at $file ($layout.sect + 40) (pack-u64 $size)
  if $delta == 0 { return }
  for field in [32 48] {
    write-at $file ($layout.seg + $field) (pack-u64 ((u64 $head ($layout.seg + $field)) + $delta))
  }
  let ncmds = u32 $head 16
  mut pos = 32
  for _ in 0..<$ncmds {
    let cmd = u32 $head $pos
    if $cmd == 0x19 and (u64 $head ($pos + 40)) >= $boundary {
      for field in [24 40] {
        write-at $file ($pos + $field) (pack-u64 ((u64 $head ($pos + $field)) + $delta))
      }
    } else if $cmd == 0x2 {
      # LC_SYMTAB: symoff, stroff
      for field in [8 16] { shift-u32 $file $head 0 ($pos + $field) $boundary $delta }
    } else if $cmd == 0xb {
      # LC_DYSYMTAB: tocoff, modtaboff, extrefsymoff, indirectsymoff, extreloff, locreloff
      for field in [32 40 48 56 64 72] { shift-u32 $file $head 0 ($pos + $field) $boundary $delta }
    } else if $cmd in [0x1d 0x26 0x29 0x80000033 0x80000034] {
      # linkedit_data_command: code signature, function starts, data in code,
      # exports trie, chained fixups
      shift-u32 $file $head 0 ($pos + 8) $boundary $delta
    } else if $cmd not-in [0x19 0xe 0xc 0x1b 0x32 0x80000028] {
      # Anything else may carry a file offset this does not know to shift.
      error make {msg: $"unhandled Mach-O load command ($cmd)"}
    }
    $pos += u32 $head ($pos + 4)
  }
}

# ELF64: the payload's section ends the highest PT_LOAD; only non-alloc
# sections and the section header table follow it in the file.
def elf-layout [buf: binary, section_off: int]: nothing -> record {
  let phoff = u64 $buf 32
  let phnum = $buf | bytes at 56..<58 | into int --endian little
  let loads = 0..<$phnum | each {|i| $phoff + $i * 56 } | where {|p| (u32 $buf $p) == 1 }
  let seg = $loads | where {|p|
    let off = u64 $buf ($p + 8)
    $section_off >= $off and $section_off < $off + (u64 $buf ($p + 32))
  }
  if ($seg | is-empty) { error make {msg: "no PT_LOAD holds the Bun payload"} }
  let seg = $seg | first
  let top = $loads | each {|p| (u64 $buf ($p + 16)) + (u64 $buf ($p + 40)) } | math max
  if (u64 $buf ($seg + 16)) + (u64 $buf ($seg + 40)) != $top {
    error make {msg: "the Bun payload's PT_LOAD is not the highest mapping, so it cannot grow"}
  }
  if (u64 $buf ($seg + 32)) != (u64 $buf ($seg + 40)) {
    error make {msg: "the Bun payload's PT_LOAD has a bss tail"}
  }
  {seg: $seg, end: ((u64 $buf ($seg + 8)) + (u64 $buf ($seg + 32)))}
}

def elf-grow [file: path, buf: binary, layout: record, section_off: int, size: int, boundary: int, delta: int] {
  let phoff = u64 $buf 32
  let phnum = $buf | bytes at 56..<58 | into int --endian little
  let shoff = u64 $buf 40
  let shnum = $buf | bytes at 60..<62 | into int --endian little
  let shdrs = $buf | bytes at $shoff..<($shoff + $shnum * 64)
  let new_shoff = if $shoff >= $boundary { $shoff + $delta } else { $shoff }

  mut found = false
  for i in 0..<$shnum {
    let p = $i * 64
    let off = u64 $shdrs ($p + 24)
    if $off == $section_off and (u32 $shdrs ($p + 4)) != 8 {
      write-at $file ($new_shoff + $p + 32) (pack-u64 $size)
      $found = true
    } else if $off >= $boundary and $delta > 0 {
      write-at $file ($new_shoff + $p + 24) (pack-u64 ($off + $delta))
    }
  }
  if not $found { error make {msg: "no ELF section holds the Bun payload"} }
  if $delta == 0 { return }

  write-at $file 40 (pack-u64 $new_shoff)
  for field in [32 40] {
    write-at $file ($layout.seg + $field) (pack-u64 ((u64 $buf ($layout.seg + $field)) + $delta))
  }
  for i in 0..<$phnum {
    let p = $phoff + $i * 56
    let off = u64 $buf ($p + 8)
    if $off >= $boundary { write-at $file ($p + 8) (pack-u64 ($off + $delta)) }
  }
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
  let section_off = $raw_start - $HEADER_SIZE
  let payload_end = $trailer_pos + ($TRAILER | bytes length)
  let table_start = $raw_start + $mod_off
  let table = $buf | bytes at $table_start..<($table_start + $mod_len)

  if (u64 $buf $section_off) != $byte_count + $OFFSETS_SIZE + ($TRAILER | bytes length) {
    error make {msg: "payload length header does not match Offsets.byte_count"}
  }

  let head = $buf | bytes at 0..<65536
  let format = match ($head | bytes at 0..<4) {
    0x[CF FA ED FE] => "macho"
    0x[7F 45 4C 46] => "elf"
    _ => { error make {msg: "neither a Mach-O 64 nor an ELF binary"} }
  }
  let layout = if $format == "macho" {
    macho-layout $head $section_off
  } else {
    elf-layout $head $section_off
  }
  let padding = $buf | bytes at $payload_end..<$layout.end
  if ($padding | bytes index-of 0x[00] --all | length) != ($padding | bytes length) {
    error make {msg: "bytes between the payload and its segment end are not padding"}
  }

  let entries = 0..<($mod_len // $MODULE_STRUCT_SIZE) | each {|i|
    let e = $table | bytes at ($i * $MODULE_STRUCT_SIZE)..<(($i + 1) * $MODULE_STRUCT_SIZE)
    {
      index: $i
      name_off: (u32 $e 0)
      name_len: (u32 $e 4)
      content_len: (u32 $e 12)
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

  # Lay the patched sources out after the existing blobs, null-terminated
  # like every other module's content.
  mut cursor = $byte_count
  mut blobs = []
  mut repoints = []
  for name in $names {
    let matches = $entries | where name == $name
    if ($matches | is-empty) { error make {msg: $"no module named ($name) in the Bun payload"} }
    let e = $matches | last
    let patched = open --raw ($extracted | path join $name) | into binary
    let len = $patched | bytes length
    $blobs = $blobs | append ($patched | bytes add --end 0x[00])
    $repoints = $repoints | append {index: $e.index, off: $cursor, len: $len}
    print $"Spliced ($name): ($e.content_len) -> ($len) bytes \(appended at ($cursor)\)"
    $cursor += $len + 1
  }
  let new_byte_count = $cursor
  let tail = [
    ...$blobs
    (pack-u64 $new_byte_count)
    ($offsets | bytes at 8..)
    $TRAILER
  ] | bytes collect
  let new_payload_end = $raw_start + $new_byte_count + $OFFSETS_SIZE + ($TRAILER | bytes length)
  let overflow = $new_payload_end - $layout.end
  let delta = if $overflow > 0 { ($overflow + $PAGE_SIZE - 1) // $PAGE_SIZE * $PAGE_SIZE } else { 0 }

  # Old payload (minus Offsets + trailer), new blobs + Offsets + trailer, zero
  # padding to the grown segment end, then everything after the segment.
  rm -f $output
  ^dd $"if=($original)" $"of=($output)" bs=1M $"count=($raw_start + $byte_count)" iflag=count_bytes status=none
  $tail | save --append $output
  ^truncate -s ($layout.end + $delta) $output
  ^tail -c $"+($layout.end + 1)" $original o>> $output
  chmod u+w $output

  write-at $output $section_off (pack-u64 ($new_byte_count + $OFFSETS_SIZE + ($TRAILER | bytes length)))
  for r in $repoints {
    let entry_pos = $table_start + $r.index * $MODULE_STRUCT_SIZE
    write-at $output ($entry_pos + 8) ([(pack-u32 $r.off) (pack-u32 $r.len)] | bytes collect)
    write-at $output ($entry_pos + 24) (0 | into binary) # bytecode offset + length
  }

  let section_size = $HEADER_SIZE + $new_byte_count + $OFFSETS_SIZE + ($TRAILER | bytes length)
  if $format == "macho" {
    macho-grow $output $head $layout $section_size $layout.end $delta
  } else {
    elf-grow $output $buf $layout $section_off $section_size $layout.end $delta
  }
  if $delta > 0 { print $"Grew the payload segment by ($delta) bytes" }
}
