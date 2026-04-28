{ pkgs, ... }:
# Pull upstream OpenSearch and sed out the one line of bundled
# jvm.options that warns at boot: `--add-opens=...arrow.memory.core`
# opens java.nio to an Arrow module 3.6.0 doesn't actually load.
# If upstream removes the line in a future bump, sed no-ops.
#
# When bumping the tag, re-run
#   nix run nixpkgs#nix-prefetch-docker -- \
#     --image-name opensearchproject/opensearch \
#     --image-tag <new-tag> --arch amd64 --os linux
# and paste the new imageDigest + hash below. Also update the
# matching `opensearchPatchedImageRef` string in postiz.nix.
let
  opensearchUpstreamImage = pkgs.dockerTools.pullImage {
    imageName = "opensearchproject/opensearch";
    finalImageName = "opensearchproject/opensearch";
    finalImageTag = "3.6.0";
    imageDigest = "sha256:57bd3c879ad27123a9a6cd75e2adba504189d3131d00a669f3baf9210bc4538c";
    hash = "sha256-n0oE4ou+mL+FPhScHfmqf1kYj6LOBlW3wOCdl02yttA=";
  };

  opensearchPatchedImage = pkgs.dockerTools.buildImage {
    name = "localhost/postiz-temporal-opensearch";
    tag = "patched";
    fromImage = opensearchUpstreamImage;
    # OpenSearch unpacks to ~3 GB; the runAsRoot VM's default 1 GB
    # disk is too small.
    diskSize = 8192;
    runAsRoot = ''
      #!/bin/bash
      sed -i \
        -e '/--add-opens=java\.base\/java\.nio=org\.apache\.arrow/d' \
        /usr/share/opensearch/config/jvm.options
    '';
    # `fromImage` provides filesystem layers only; OCI Config is whatever
    # we declare here. Values mirror `podman inspect` of the upstream tag.
    config = {
      User = "1000";
      ExposedPorts = {
        "9200/tcp" = { };
        "9300/tcp" = { };
        "9600/tcp" = { };
        "9650/tcp" = { };
      };
      Env = [
        "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/share/opensearch/jdk/bin:/usr/share/opensearch/bin"
        "JAVA_HOME=/usr/share/opensearch/jdk"
        "LD_LIBRARY_PATH=/usr/share/opensearch/plugins/opensearch-knn/lib"
      ];
      Entrypoint = [ "./opensearch-docker-entrypoint.sh" ];
      Cmd = [ "opensearch" ];
      WorkingDir = "/usr/share/opensearch";
    };
  };
in
{
  # The patched OpenSearch image lives in the Nix store as a docker
  # tarball. This service registers it with podman's storage so the
  # postiz-temporal-opensearch.container unit can reference it by tag.
  # `podman load` is idempotent — re-runs are no-ops once the image
  # is present.
  systemd.services.load-postiz-temporal-opensearch-image = {
    description = "Load the patched OpenSearch image into podman storage";
    wantedBy = [ "multi-user.target" ];
    before = [ "postiz-temporal-opensearch.service" ];
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      podman load -i ${opensearchPatchedImage}
    '';
  };
}
