{
  lib,
  buildNpmPackage,
  fetchurl,
}:
let
  notoSansMono = fetchurl {
    name = "NotoSansMono.ttf";
    url = "https://raw.githubusercontent.com/notofonts/notofonts.github.io/noto-monthly-release-2026.08.01/fonts/NotoSansMono/unhinted/variable-ttf/NotoSansMono%5Bwdth%2Cwght%5D.ttf";
    hash = "sha256-BLG//8WYEU+ZjGDzE/emTfbJEez+1Hok4n8Dsd80v2Y=";
  };

  sourceSerif = fetchurl {
    name = "SourceSerif4Variable-Roman.otf";
    url = "https://raw.githubusercontent.com/adobe-fonts/source-serif/4.005R/VAR/SourceSerif4Variable-Roman.otf";
    hash = "sha256-hntzxqlUpKZGFpBtF5+UVyp0h5Ch0CLr7v8H9W6gIho=";
  };

  notoSerifSC = fetchurl {
    name = "NotoSerifSC-VF.otf";
    url = "https://raw.githubusercontent.com/notofonts/noto-cjk/Serif2.003/Serif/Variable/OTF/Subset/NotoSerifSC-VF.otf";
    hash = "sha256-cbTT3tLZD/Q7t1pOSM2+Fw8LjVSG3In/h/KhcotW2mQ=";
  };

  jetBrainsMono = fetchurl {
    name = "JetBrainsMono.ttf";
    url = "https://raw.githubusercontent.com/JetBrains/JetBrainsMono/v2.304/fonts/variable/JetBrainsMono%5Bwght%5D.ttf";
    hash = "sha256-ZioZbVjxGDvy13QottUoP+P0UWGrAhvqQDa8mOXKwBY=";
  };

  geist = fetchurl {
    name = "Geist.ttf";
    url = "https://raw.githubusercontent.com/vercel/geist-font/v1.7.2/fonts/Geist/variable/Geist%5Bwght%5D.ttf";
    hash = "sha256-c4lOBEjK6QqStsL4cyt7uay3uUxBi/9Vna1KGOHellk=";
  };

  # Root-level build inputs are discovered rather than listed by hand. An explicit list
  # fails *evaluation* — not just the build — the next time upstream adds a root config
  # file, which is exactly how `next-env.d.ts` broke this flake: it is gitignored, so it
  # is never in a clean checkout, yet the fileset demanded it.
  #
  # `next-env.d.ts` stays excluded explicitly: `next build` generates it, so a local
  # build may have left one in the tree and it must not change the source hash.
  buildFileExtensions = [
    ".ts"
    ".tsx"
    ".mts"
    ".mjs"
    ".cjs"
    ".js"
    ".json"
  ];

  rootEntries = builtins.readDir ../.;

  rootBuildFiles = lib.fileset.unions (
    map
      (name: lib.fileset.maybeMissing (../. + "/${name}"))
      (
        builtins.filter
          (
            name: rootEntries.${name} == "regular"
              && builtins.any (suffix: lib.hasSuffix suffix name) buildFileExtensions
              && name != "next-env.d.ts"
          )
          (builtins.attrNames rootEntries)
      )
  );

  productionLib = lib.fileset.difference ../lib (
    lib.fileset.fileFilter (file: lib.hasInfix ".test." file.name) ../lib
  );

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../app
      ../bin
      ../components
      ../hooks
      productionLib
      ../public
      ../scripts
      rootBuildFiles
    ];
  };
  version = (builtins.fromJSON (builtins.readFile ../package.json)).version;
in
buildNpmPackage (finalAttrs: {
  pname = "ompweb";
  inherit src version;

  postPatch = ''
    mkdir -p app/fonts
    cp ${notoSansMono} app/fonts/NotoSansMono.ttf
    cp ${sourceSerif} app/fonts/SourceSerif4Variable-Roman.otf
    cp ${notoSerifSC} app/fonts/NotoSerifSC-VF.otf
    cp ${jetBrainsMono} app/fonts/JetBrainsMono.ttf
    cp ${geist} app/fonts/Geist.ttf
  '';

  # Swap next/font/google for next/font/local. Google serves the font binaries over the
  # network at build time and the Nix sandbox has none, so this is the only step in the
  # build that needs substituting.
  #
  # It lives in preBuild, not postPatch, on purpose: buildNpmPackage forwards postPatch
  # to the separate `npmDeps` derivation, which runs in a stdenv with no node on PATH.
  # Putting a `node` invocation in postPatch therefore breaks every build that has to
  # recompute npmDepsHash — i.e. every sync that touches package-lock.json. preBuild is
  # not forwarded, so it runs only in the derivation that actually runs `next build`.
  #
  # A script rather than a `patches` diff, because a diff against app/layout.tsx has to
  # restate that file's import block and every font call verbatim, and so breaks the
  # moment upstream edits layout.tsx for any unrelated reason.
  preBuild = ''
    node ${./local-fonts-shim.mjs} app/layout.tsx app/fonts
  '';

  npmDepsHash = "sha256-HxT+m6bI0I3t9sqsSgHun6oXve3WtIEmkFpCoBplrC4=";

  # npmPackFlags = [ "--ignore-scripts" ];

  meta = {
    description = "Local web UI for the oh-my-pi (omp) coding agent";
    license = lib.licenses.mit;
    # The package installs five binaries (ompweb plus the tray/launchd/systemd helpers).
    # Without an explicit mainProgram, `nix run` only works by accident — because the
    # package name happens to match a binary name.
    mainProgram = "ompweb";
  };
})
