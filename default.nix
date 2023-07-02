{
  pkgs ? import <nixpkgs> {},
  cacheBreaker ? null,

  usePathSource ? true,
  useStringifiedPath ? true,
  useFilteredPath ? true,
  useLinkFarm ? true,

  ...
}:
let
  lib = pkgs.lib;
  modeFlags = {
    inherit usePathSource useStringifiedPath useFilteredPath useLinkFarm;
  };
  cacheBreakerCalc = if builtins.isNull cacheBreaker
    then (builtins.substring 0 5
      (builtins.hashString "sha256"
        (builtins.toJSON modeFlags)))
    else cacheBreaker;
  subdirSource = if usePathSource then (import (builtins.path { name = "subdir-source-nonrepro"; path = ./subdir.d; })) else (import ./subdir.d);
  subdir = subdirSource {
    inherit (pkgs) stdenv coreutils;
    version = cacheBreakerCalc;
  };
  output = lib.trivial.pipe subdir (
    # Does "${stringification}" of derivation handles change behaviour?
    (lib.optional useStringifiedPath (prev: if useStringifiedPath then "${prev}" else prev))

    # Does builtin.path filtration change behaviour?
    ++ (lib.optional useFilteredPath (prev: builtins.path {
      path = prev;
      name = "subdir-filtered";
      filter = path: type: true;
    }))

    # Does builtin.path pkgs.linkFarm change behaviour?
    ++ (lib.optional useLinkFarm (prev: pkgs.linkFarm "linkfarm-combined-dir" [
        {
          name = "hello.txt";
          path = "${prev}/hello.txt";
        }
        {
          name = "world.txt";
          path = "${prev}/world.txt";
        }
        {
          name = "space.txt";
          path = "${pkgs.emptyFile}";
        }
      ]
    ))

  );

  # Build a derivation with the content using runCommand to copy it over
  resultDerivation =
    ((pkgs.runCommand
      "lst-repro"
      { version = cacheBreakerCalc; }
      ''
        set -e
        ls "${output}"
        mkdir -p $out
        cat "${output}/hello.txt" "${output}/world.txt" > "$out/helloworld.txt"
      '')
        .overrideAttrs(prev: {
          passthru.modeFlags = modeFlags;
          inherit cacheBreakerCalc;
        })
    );
in resultDerivation
