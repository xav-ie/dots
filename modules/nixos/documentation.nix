{
  # Keeps every system package's -doc output (~64 MiB) out of the closure;
  # man pages are a separate option and stay.
  flake.modules.nixos.base.documentation.doc.enable = false;
}
