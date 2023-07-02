{
  description = "Break Lazy Source Trees in Nix with Source Tree Abstraction";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          evalTarget = import ./default.nix;
          pkgs = nixpkgs.legacyPackages.${system};
          lib = pkgs.lib;
          concatSep = sep: lib.strings.concatMapStringsSep sep (lib.trivial.id);
        in
        {
          packages.default = evalTarget { inherit pkgs; };
          packages.noRepro = evalTarget { inherit pkgs; usePathSource = true; useFilteredPath = false; };
          packages.report = (
            let
              buildCacheBreaker = configurationModeFlags: builtins.substring 0 5 (builtins.hashString "sha256" (builtins.toJSON configurationModeFlags)); 
              writeAttemptOutPath = (nixBuildPath: srcPath: configuration:
                let
                  breaker = buildCacheBreaker (configuration // { inherit nixBuildPath; });
                  argValue = value: if (builtins.typeOf value) == "bool" then (if value then "true" else "false") else "\"${value}\"";
                  buildArg = { name, value }: "--arg${if (builtins.typeOf value) == "string" then "str" else ""} ${name} ${argValue value}";
                  configArgs = concatSep " " (lib.attrsets.mapAttrsToList (k: v: buildArg { name = k; value = v; }) configuration);
                in
                ''${nixBuildPath} ${srcPath}/default.nix ${configArgs} ${buildArg { name = "cacheBreaker"; value = "$(echo \\\"$nixBuildExe\\\" | sha256sum -t | head -c5)${breaker}"; }}''
              );
              availableModeFlags = builtins.filter (lib.strings.hasPrefix "use") (builtins.attrNames (lib.trivial.functionArgs evalTarget));
              configurations = lib.attrsets.cartesianProductOfSets (builtins.listToAttrs (map (modeFlag: { name = modeFlag; value = [false true]; }) availableModeFlags));
              selectEnabledFlags = configurationModeFlags: (builtins.attrNames (lib.attrsets.filterAttrs (k: v: v) configurationModeFlags));
              displayModeFlags = configuration: concatSep ", " (map (lib.strings.removePrefix "use") (lib.lists.sort (a: b: a < b) (selectEnabledFlags configuration)));
              reportCommands = map (configuration: builtins.traceVerbose "Generating report for ${builtins.toJSON configuration}" ''
                # echo "${writeAttemptOutPath "$nixBuildExe" "$src" configuration}"
                OUTPATH=$(${writeAttemptOutPath "$nixBuildExe" "$src" configuration} 2>/dev/null || echo "/failed")
                if [[ -d "$OUTPATH" && -f "$OUTPATH/helloworld.txt" || -d "$OUTPATH" && -f "$OUTPATH/hello.txt" ]]; then 
                  echo "${displayModeFlags configuration}: $OUTPATH"
                else
                  echo "${displayModeFlags configuration}: failed"
                fi
              '') configurations;
              reportScript = ''
                set -e
                echo "Report of various success modes:"
                ${concatSep "\n" reportCommands}
              '';
              content = pkgs.writeTextFile {
                name = "gen-report.sh";
                text = reportScript;
                executable = true;
              };
            in {
              inherit content; # Body of the report
              inherit availableModeFlags; # Display with `nix eval .#report.availableModeFlags`
              inherit configurations; # Display pretty output with `nix eval .#report.configurations --json | nix-shell -p yq --command yq`
            }
          );
        }
      );
}
