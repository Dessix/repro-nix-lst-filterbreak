{ version ? "dev", stdenv, coreutils }:
stdenv.mkDerivation {
  pname = "subdir-content";
  inherit version;
  src = ./.;

  phases = [ "buildPhase" "installPhase" ];

  buildInputs = [ coreutils ];
  buildPhase = ''
    cp -r $src/* .
  '';

  installPhase = ''
    mkdir -p $out
    cp -r * $out/
  '';
}
