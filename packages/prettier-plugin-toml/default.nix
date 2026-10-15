# prettier-plugin-toml from the npm registry. v3 wraps tombi's WASM formatter;
# its three runtime deps have no dependencies of their own, so they are fetched
# as plain tarballs and laid out by hand instead of carrying a lockfile. Bump the
# deps alongside the plugin to whatever its package.json ranges resolve to.
{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  pname = "prettier-plugin-toml";
  deps = {
    "@dual-bundle/import-meta-resolve" = fetchurl {
      url = "https://registry.npmjs.org/@dual-bundle/import-meta-resolve/-/import-meta-resolve-4.2.1.tgz";
      hash = "sha256-SbQjed4mVsviH6MsbAVGhqfUiBO+M7mBsSVzH6bdkiY=";
    };
    "@tombi-toml/wasm-lib" = fetchurl {
      url = "https://registry.npmjs.org/@tombi-toml/wasm-lib/-/wasm-lib-1.8.4.tgz";
      hash = "sha256-nd/9MPDoYij1E37VKExRMBBAyZPn1Y/y2YW8QzKWcJU=";
    };
    smol-toml = fetchurl {
      url = "https://registry.npmjs.org/smol-toml/-/smol-toml-1.9.1.tgz";
      hash = "sha256-Ssg5LxkYwipDZr4ZBHz1OqQmRgd9THEbLvcyY77vsXI=";
    };
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  inherit pname;
  version = "3.0.2";

  src = fetchurl {
    url = "https://registry.npmjs.org/prettier-plugin-toml/-/prettier-plugin-toml-${finalAttrs.version}.tgz";
    hash = "sha256-iQ82rawcKd3C92IfupO7uZsD/cnplHj+yc7yN52jw6w=";
  };

  installPhase = ''
    runHook preInstall

    dir=$out/lib/node_modules/${pname}
    mkdir -p $dir
    cp -r . $dir
    ${lib.concatMapAttrsStringSep "\n" (name: tarball: ''
      mkdir -p $dir/node_modules/${name}
      tar -xzf ${tarball} --strip-components=1 -C $dir/node_modules/${name}
    '') deps}

    runHook postInstall
  '';

  passthru = {
    packageName = pname;
  };

  meta = {
    description = "Prettier TOML plugin powered by tombi";
    homepage = "https://github.com/un-ts/prettier/tree/master/packages/toml";
    license = lib.licenses.mit;
    maintainers = [ ];
  };
})
