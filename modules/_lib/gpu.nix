# Single source of truth for praesidium's GPU facts.
#
# These are needed in two layers that can't see each other: the overlay layer
# (overlays/default.nix builds pkgs *before* the module system evaluates, so it
# can't read nixpkgs.config) and the NixOS/home modules. Both import this file
# so a GPU swap is a one-line edit here.
{
  # NVIDIA RTX 3060 Ti (GA104, Ampere) → CUDA compute capability 8.6 (sm_86).
  # Pinning a single arch instead of the full fat binary is what makes the
  # local CUDA builds (onnxruntime/whisper-cpp) fast. Update on a GPU change.
  cudaCapabilities = [ "8.6" ];

  # NVIDIA Vulkan ICD manifest, installed under /run/opengl-driver by
  # hardware.graphics. Consumers that bypass the normal loader search path
  # (headless Chrome, AppImage-derived apps) point VK_ICD_FILENAMES at it.
  vulkanIcd = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json";
}
