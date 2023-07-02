{ version ? "dev", stdenv, coreutils }:
stdenv.mkDerivation {
  pname = "subdir-content";
  inherit version;
  src = ./.;

  phases = [ "build" "install" ];

  buildInputs = [ coreutils ];
  buildPhase = ''
    cp -r $src/* .
  '';

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out
    cp -r * $out/
  '';
}
