#!/usr/bin/env nu --stdin

# Item shell for the speaker icon. The icon image — and its per-level changes —
# is rendered and driven by volume.nu's tween (see `vol-icon-image` there) so it
# fills through its states in step with the counting number. This plugin only
# owns the static item props + the hover box, so it no longer subscribes to
# volume_change (volume.nu is the single owner of the image, which avoids the two
# items fighting over it mid-tween).
# Geometry (icon.width=24 and all paddings) is owned by the `sb-cluster volume`
# primitive in sketchybarrc.nu, and the icon image is driven by volume.nu's tween
# (see `vol-icon-image` there). This item therefore has nothing to render itself;
# it exists only for its half of the shared hover highlight (mouse events).
def main [] { }
