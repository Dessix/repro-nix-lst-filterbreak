{
  pkgs ? import <nixpkgs> {},
  shouldRepro ? false,
  ...
}:
let
  subdirSource = if shouldRepro then (import ./subdir.d) else (import (builtins.path { name = "subdir-source-nonrepro"; path = ./subdir.d; }));
  subdir = subdirSource {
    inherit (pkgs) stdenv coreutils;
    version = "testing2";
  };
  filteredPath = builtins.path {
    path = "${subdir.outPath}";
    name = "subdir-filtered";
    filter = path: type:
      true;
      #builtins.elem (baseNameOf path) [ "hello.txt" "world.txt" ];
  };
  linkFarmed = pkgs.linkFarm "linkfarm-combined-dir" [
    {
      name = "hello.txt";
      path = "${filteredPath}/hello.txt";
    }
    {
      name = "world.txt";
      path = "${filteredPath}/world.txt";
    }
    {
      name = "space.txt";
      path = "${pkgs.emptyFile}";
    }
  ];
  self = pkgs.stdenv.mkDerivation {
    name = "hello-world-lst-repro";
    version = "0.0.2";
    installPhase = ''
      cat "$linkFarmed/hello.txt" "$linkFarmed/world.txt" > "$out/helloworld.txt"
    '';
    buildInputs = [linkFarmed];
  };
in self
