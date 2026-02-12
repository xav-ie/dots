#!/usr/bin/awk -f
# Lint: flag Nix files with unannotated, non-exempt '' blocks of N+ lines.
# Usage: awk -v min_lines=5 -f nix-multiline-lint.awk file1.nix file2.nix ...
# Exit 1 if any violations found.

BEGIN {
    if (!min_lines) min_lines = 5
    violations = 0
    exempt_re = "(installPhase|postPatch|prePatch|postInstall|preInstall" \
                "|buildPhase|checkPhase|configurePhase|fixupPhase" \
                "|unpackPhase|patchPhase|preBuild|postBuild" \
                "|preCheck|postCheck|preConfigure|postConfigure" \
                "|preFixup|postFixup|description)[[:space:]]*="
}

# Count '' delimiters on a line, excluding '''' escapes
function count_delimiters(line,    tmp, count) {
    tmp = line
    gsub(/''''/, "", tmp)
    count = 0
    while (match(tmp, /''/)) {
        count++
        tmp = substr(tmp, RSTART + 2)
    }
    return count
}

# Reset per-file state
FNR == 1 {
    in_block = 0
    prev = ""
    file_flagged = 0
}

# Outside a block: look for opening ''
# Opening '' is at end of line (not '''')
# Skip single-line '' strings (even delimiter count = balanced)
!in_block && /''[[:space:]]*$/ && !/''''[[:space:]]*$/ {
    if (count_delimiters($0) % 2 == 0) {
        prev = $0
        next
    }

    in_block = 1
    block_start = FNR
    block_lines = 0

    # Annotated: # on current line or previous line (e.g. = # nu)
    annotated = ($0 ~ /#/ || prev ~ /#/) ? 1 : 0

    # Exempt: standard derivation phases, description, etc.
    exempt = ($0 ~ exempt_re || prev ~ exempt_re) ? 1 : 0

    prev = $0
    next
}

# Inside a block: detect closing '' then count content lines
in_block {
    # Closing '': starts with optional whitespace, then '' followed by ; ) } ] or EOL
    # Must not be '''' (escape) or ''$ (dollar escape) or ''\ (backslash escape)
    if (/^[[:space:]]*''[;)}\]]/ || /^[[:space:]]*''[[:space:]]*$/) {
        if (!/^[[:space:]]*''''/) {
            in_block = 0
            if (block_lines >= min_lines && !annotated && !exempt) {
                if (!file_flagged) {
                    print FILENAME
                    file_flagged = 1
                    violations++
                }
            }
        }
    }

    # Only count content lines, not the closing delimiter
    if (in_block) {
        block_lines++
    }
}

{ prev = $0 }

END { exit (violations > 0) ? 1 : 0 }
