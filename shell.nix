{
  pkgs ? import <nixpkgs> {},
  usePathSource ? true,
  useStringifiedPath ? true,
  useFilteredPath ? true,
  useLinkFarm ? true,
  useReproDerivation ? true,
  cacheBreaker ? "1",
  ...
}:
let
  lib = pkgs.lib;

  subdirSource = if usePathSource then (import (builtins.path { name = "subdir-source-nonrepro"; path = ./subdir.d; })) else (import ./subdir.d);
  subdir = subdirSource {
    inherit (pkgs) stdenv coreutils;
    version = cacheBreaker;
  };
  output = lib.trivial.pipe subdir (
    (lib.optional useStringifiedPath (prev: if useStringifiedPath then "${prev}" else prev))
    ++ (lib.optional useFilteredPath (prev: builtins.path {
      path = prev;
      name = "subdir-filtered";
      filter = path: type: true;
    }))
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
    ++ (lib.optional useReproDerivation (prev:
      pkgs.runCommand "hello-world-lst-repro-${cacheBreaker}" {
        version = cacheBreaker;
      }
      ''
        set -e
        ls "${prev}"
        mkdir -p $out
        cat "${prev}/hello.txt" "${prev}/world.txt" > "$out/helloworld.txt"
      '')
    )
  );
in output
