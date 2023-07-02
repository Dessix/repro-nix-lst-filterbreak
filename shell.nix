{
  pkgs,
  ...
}:
let
  subdir = (import ./subdir.d) {
    inherit (pkgs) stdenv coreutils;
  };
  filteredPath = builtins.path {
    path = "${subdir}";
    name = "subdir-filtered";
    filter = path: type:
      builtins.elem (baseNameOf path) [ "hello.txt" "world.txt" ];
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
    version = "0.0.1";
    buildPhase = ''
      ls "${linkFarmed}"
      cat "${linkFarmed}/hello.txt" "${linkFarmed}/world.txt" > "$out/helloworld.txt"
    '';
  };
in self
