{
  flake.modules.nixos.linux = {
    # This host runs an mmap'd embedding model alongside two full Postiz stacks
    # and the observability pod, so committed memory sits above the 32GB of RAM
    # and the kernel leans on the disk swapfile. The stock swappiness of 60
    # makes it evict
    # *active* anonymous pages (bar, browser, editor) under load, and faulting
    # those back from the slow swapfile is what stalls the UI. Drop it so the
    # kernel prefers reclaiming rebuildable page cache and only swaps anon
    # memory when genuinely pressured — cold idle pages still park in swap.
    boot.kernel.sysctl."vm.swappiness" = 10;

    # Cap the build tree's memory so a runaway rebuild OOM-kills a build
    # process, not the desktop. Builds run in nix-daemon.service's cgroup.
    #
    # The cap alone is not enough, and both extra settings here are load-bearing:
    #
    # MemoryMax has to leave room for everything else. llama-server, two Postiz
    # stacks, the grafana/loki/prometheus trio, home-assistant and the desktop
    # together want well over half of this host's 32GB, so a build tree allowed
    # to grow into the high teens drains the *global* pool while still sitting
    # inside its own cgroup — the kernel then declares a CONSTRAINT_NONE OOM
    # that the cgroup limit has no say over.
    #
    # OOMScoreAdjust decides who dies when that happens anyway. systemd gives
    # user-session services +200, so at the default 0 the build tree outranks
    # the desktop and the kernel reaps the compositor instead of a compiler.
    # Outrank the desktop deliberately: a dead build is a retry, a dead session
    # is a reboot.
    # Sized from measurement, not arithmetic: CUDA compilers are the fat case at
    # ~0.9GB resident each (cicc/ptxas), against ~0.3GB for ordinary C++. With
    # cores x max-jobs = 16 that is ~14GB of anonymous memory at peak, so Max
    # has to sit above that or a cgroup OOM fails the build instead of merely
    # slowing it. High sits below it as the throttle: holding the tree at its
    # ceiling cost 2.4s of total stall across a multi-hour rebuild, because most
    # of what gets reclaimed there is page cache.
    systemd.services.nix-daemon = {
      serviceConfig = {
        MemoryHigh = "14G";
        MemoryMax = "18G";
        MemorySwapMax = "4G";
        OOMScoreAdjust = 500;
      };
    };
  };
}
