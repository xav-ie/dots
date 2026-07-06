{
  flake.modules.nixos.linux = {
    # This host runs a ~9GB local model (llama-server) alongside two full Postiz
    # stacks, so committed memory sits above the 32GB of RAM and the kernel
    # leans on the disk swapfile. The stock swappiness of 60 makes it evict
    # *active* anonymous pages (bar, browser, editor) under load, and faulting
    # those back from the slow swapfile is what stalls the UI. Drop it so the
    # kernel prefers reclaiming rebuildable page cache and only swaps anon
    # memory when genuinely pressured — cold idle pages still park in swap.
    boot.kernel.sysctl."vm.swappiness" = 10;

    # Cap the build tree's memory so a runaway rebuild OOM-kills a build
    # process, not the desktop. Builds run in nix-daemon.service's cgroup.
    systemd.services.nix-daemon.serviceConfig = {
      MemoryHigh = "14G";
      MemoryMax = "18G";
      MemorySwapMax = "8G";
    };
  };
}
