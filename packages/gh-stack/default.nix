# gh-stack — GitHub's official CLI extension for native stacked PRs.
#
# Not in nixpkgs. Built from the tagged release and wired into
# programs.gh.extensions, which links bin/gh-stack as `gh stack`.
#
# go.mod asks for go 1.26.0, newer than the pinned nixpkgs' go, so this is
# called from pkgs-bleeding in packages/default.nix.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  git,
}:
buildGoModule rec {
  pname = "gh-stack";
  version = "0.2.1";

  src = fetchFromGitHub {
    owner = "github";
    repo = "gh-stack";
    tag = "v${version}";
    hash = "sha256-Mq4jAqeSHDuCiDYSa40okrq06UhC3dZGjgCXJKMbgzU=";
  };

  vendorHash = "sha256-TC1mSXYjOQo00fb2yuGdk1rl6z6rp0WT3AmzXomPzis=";

  # the integration tests drive a real git against throwaway repos
  nativeCheckInputs = [ git ];

  # the modifyview tests look branches up in the cwd's repo, which the
  # unpacked tarball isn't
  preCheck = ''
    git init -q
  '';

  # same override upstream's release workflow uses, so `gh stack --version`
  # reports the release instead of "dev"
  ldflags = [
    "-s"
    "-w"
    "-X=github.com/github/gh-stack/cmd.Version=${version}"
  ];

  meta = with lib; {
    description = "GitHub CLI extension for managing stacked branches and pull requests";
    homepage = "https://github.com/github/gh-stack";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "gh-stack";
  };
}
