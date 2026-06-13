// Linux/NVIDIA hardware video decode (VA-API → NVDEC via nvidia-vaapi-driver,
// with LIBVA_DRIVER_NAME=nvidia from the Hyprland session). Appended to each
// profile's user.js so it's applied early: the gfx feature decision runs at
// GPU-process startup, before package autoconfig prefs land, so these must be
// user_prefs read up front or Firefox force-disables decode ("disabled by
// gfxVars") and silently falls back to CPU. Verified via MOZ_LOG
// (IsHardwareAccelerated=1) — moves video decode off the CPU onto the GPU.
user_pref("media.ffmpeg.vaapi.enabled", true);
user_pref("media.rdd-ffmpeg.enabled", true);
// NVIDIA is blocklisted for HARDWARE_VIDEO_DECODING on Linux; force past it.
user_pref("media.hardware-video-decoding.force-enabled", true);
// NVIDIA fails Firefox's dmabuf auto-detection; VA-API frames are shared as
// dmabufs, so force it on.
user_pref("widget.dmabuf.force-enabled", true);
// nvidia-vaapi-driver requires Firefox's EGL backend; without this the GPU
// process can't validate the VA-API surface path and disables decode wholesale.
user_pref("gfx.x11-egl.force-enabled", true);

// Extras carried over from the pre-dendritic config (commit bb9410e), which
// the migration dropped along with the rest of the VA-API prefs.
// WebRender's native compositor must stay OFF on NVIDIA + Wayland or it
// corrupts rendering / tears. https://bugzilla.mozilla.org/show_bug.cgi?id=1898476
user_pref("gfx.webrender.compositor", false);
user_pref("gfx.webrender.compositor.force-enabled", false);
// AV1 software/HW decode (YouTube serves a lot of AV1).
user_pref("media.av1.enabled", true);
// dmabuf-backed GL textures for zero-copy WebGL/video on Wayland.
user_pref("widget.dmabuf-textures.enabled", true);
user_pref("widget.wayland-dmabuf-textures.enabled", true);
user_pref("widget.wayland-dmabuf-webgl.enabled", true);
