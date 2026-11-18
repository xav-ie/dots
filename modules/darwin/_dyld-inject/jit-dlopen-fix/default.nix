# jit-dlopen-fix: on this boot config, dlopen resets the calling thread's
# MAP_JIT write-protect state to execute. JDK 21+ caches that state, so it
# writes its code cache after loading libjimage and dies with SIGBUS (e.g.
# Minecraft). The dylib tracks pthread_jit_write_protect_np per thread and
# re-applies it after dlopen/dlclose.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.dyldInject.jitDlopenFix;
  jit-dlopen-fix = pkgs.callPackage ./pkgs/jit-dlopen-fix { };
in
{
  options.services.dyldInject.jitDlopenFix.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Re-apply each thread's JIT write-protect state after dlopen.";
  };

  config = lib.mkIf cfg.enable {
    services.dyldInject.libraries = [ "${jit-dlopen-fix}/lib/JitDlopenFix.dylib" ];
  };
}
