{
  lib,
  buildNpmPackage,
  fetchpatch,
  src,
}:
buildNpmPackage {
  pname = "protonmail-mcp-server";
  version = "1.0.1-${src.shortRev or "unstable"}";

  inherit src;

  # All our fixes/features as one linear stack (main..save_draft) from the fork,
  # in dependency order: deadlock → cross-folder uid → getEmailById fetchOne →
  # attachment-cache bloat → light list/search fetch → search query →
  # required-param validation → IMAP timeouts → save_draft. Upstream PRs #59–#67
  # at github.com/xav-ie/protonmail-mcp-server; pulled from the compare range
  # until they merge.
  patches = [
    (fetchpatch {
      url = "https://github.com/xav-ie/protonmail-mcp-server/compare/653322c...1a296ae.patch";
      hash = "sha256-UStNSnbnEbov7RdINPuKmt7ZifY76QLZ3qyAhfYSDD4=";
    })
  ];

  npmDepsHash = "sha256-D6UTvXuM5EVA3AYn3IsNpO4OCJsP5KqlBQUC3xvUuJo=";

  meta = {
    description = "ProtonMail MCP server over Proton Bridge SMTP+IMAP";
    homepage = "https://github.com/barhatch/protonmail-mcp-server";
    license = lib.licenses.mit;
    mainProgram = "protonmail-mcp-server";
  };
}
