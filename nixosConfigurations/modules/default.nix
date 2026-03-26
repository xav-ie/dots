{ ... }:
{
  imports = [
    ../../lib/common
    ./atop
    ./bluetooth.nix
    ./ccache.nix
    ./chrome.nix
    ./cloudflared.nix
    ./dnsmasq.nix
    ./executor.nix
    ./fusion.nix
    ./hardware-configuration.nix
    ./home-assistant.nix
    ./hyprland.nix
    ./jellyfin.nix
    ./lightrag.nix
    ./linux-home-manager.nix
    ./mcp-proxy
    ./n8n.nix
    ./nginx.nix
    ./opencode.nix
    ./nix-config.nix
    ./noisetorch
    ./plover.nix
    ./podman.nix
    ./portainer.nix
    ./postiz.nix
    ./power-save
    ./quadlet.nix
    ./quartz.nix
    ./remote-builder.nix
    ./sops.nix
    ./spdf.nix
    ./sudo-askpass.nix
    ./systemd.nix
    ./tailscale.nix
    ./traefik.nix
    ./udisks.nix
    ./uptime-kuma.nix
    ./vllm.nix
    # not currently routing correctly...
    # ./twingate.nix
  ];

  config = {
    services.reverse-proxy.enable = false;

    # vLLM for local AI code completion (cursortab)
    # Accessible at https://vllm.lalala.casa via traefik
    services.vllm = {
      enable = false;
      model = "Xenova/sweep-next-edit-1.5B";
      # 3060 Ti has 8GB, leave headroom for desktop/browser
      gpuMemoryUtilization = 0.7;
      # Limit context to save VRAM (4k is plenty for code completions)
      maxModelLen = 4096;
      # Disable CUDA graphs to save VRAM
      enforceEager = true;
      # Performance optimizations
      enablePrefixCaching = true;
      enableChunkedPrefill = true;
      # Ngram speculation - good for edit prediction
      ngramSpeculation = {
        enable = true;
        lookupMax = 4;
        lookupMin = 2;
        numTokens = 8;
      };
    };
  };
}
