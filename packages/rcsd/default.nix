# rcsd: the Go backend of the xav-ie/rcsd fork of OpenMessage (Google
# Messages over SMS/RCS, web UI and MCP). Source is the `rcsd-src` flake
# input; bump it and `vendorHash` together. The Go module is still
# github.com/maxghenis/openmessage, so the binary is `openmessage`.
{
  lib,
  buildGoModule,
  src,
}:
buildGoModule (finalAttrs: {
  pname = "rcsd";
  version = "0-unstable-${builtins.substring 0 8 src.lastModifiedDate}";
  inherit src;

  vendorHash = "sha256-c0DFcF6PUGqyerOkzTMgyIpHtgj0dF+D6erVNZKi6Hs=";
  subPackages = [ "." ];
  env.CGO_ENABLED = 0;
  ldflags = [
    "-s"
    "-w"
    "-X main.version=${finalAttrs.version}"
  ];
  # Tests drive live sessions and Playwright.
  doCheck = false;

  meta = {
    description = "Local-first Google Messages (SMS/RCS) backend with a web UI and an MCP server";
    homepage = "https://github.com/xav-ie/rcsd";
    license = lib.licenses.mit;
    mainProgram = "openmessage";
  };
})
