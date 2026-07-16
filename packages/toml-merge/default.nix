# toml-merge: deep-merge a fragment TOML into a target TOML in place,
# format-preserving (tomlkit) — comments, key order, quote style, and every
# key the fragment doesn't mention are left untouched. Overlapping tables are
# merged recursively; leaf values from the fragment win.
#
# The fragment's own structure decides what gets touched, so there's no key to
# target: a fragment of just `[theme.custom]` only rewrites that table. Built
# for syncing a generated section (e.g. a theme from a flake) into a live,
# hand-editable config without a reserialize (which strips comments).
#
#   toml-merge <target.toml> <fragment.toml>
{
  writers,
  python3Packages,
}:
writers.writePython3Bin "toml-merge"
  {
    libraries = [ python3Packages.tomlkit ];
  } # py
  ''
    import sys

    import tomlkit
    from tomlkit.items import Table


    def merge(dst, src):
        for key, value in src.items():
            if isinstance(value, Table) and isinstance(dst.get(key), Table):
                merge(dst[key], value)
            else:
                dst[key] = value


    target, fragment = sys.argv[1], sys.argv[2]

    dst = tomlkit.parse(open(target).read())
    merge(dst, tomlkit.parse(open(fragment).read()))

    open(target, "w").write(tomlkit.dumps(dst))
  ''
