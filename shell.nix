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
  self = pkgs.stdenv.mkDerivation {
    name = "hello-world-lst-repro";
    version = "0.0.1";
    buildPhase = ''
      ls "${filteredPath}"
      cat "${filteredPath}/hello.txt" "${filteredPath}/world.txt" > "$out/helloworld.txt"
    '';
  };
in self
