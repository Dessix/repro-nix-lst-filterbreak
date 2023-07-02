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
          nix-stable = pkgs.nixVersions.nix_2_16;
          nix-lst = nix-stable.overrideAttrs (old: {
            version = old.version + "-lst";
            src = pkgs.fetchFromGitHub {
              owner = "edolstra";
              repo = "nix";
              rev = "f355c3437c4abeeaadb28726b49453135c6868c0";
              hash = "sha256-O/sLP84mscj1+TkIcn9+leA5tiHIglUaY2tjjziXRFQ=";
            };
            buildInputs = old.buildInputs ++ [ pkgs.libgit2 ];
          });
          lib = pkgs.lib;
        in
        {
          packages.default = evalTarget { inherit pkgs; };
          packages.noRepro = evalTarget { inherit pkgs; useFilteredPath = false; };

          # I'm sorry for the following monstrosity.
          #
          # Nix did not make it easy to generate combinatoric tests for multiple versions of
          # itself, and recursive-nix is not yet supported without an experimental flag.
          # Besides, recursive-nix would probably not support multiple mismatched versions anyway.
          packages.report = (
            let
              buildCacheBreaker = configurationModeFlags: builtins.substring 0 5 (builtins.hashString "sha256" (builtins.toJSON configurationModeFlags)); 
              writeAttemptOutPath = (nixBuildPath: srcPath: configuration:
                let
                  breaker = buildCacheBreaker (configuration // { inherit nixBuildPath; });
                  argValue = value: if (builtins.typeOf value) == "bool" then (if value then "true" else "false") else "\"${value}\"";
                  buildArg = { name, value }: if name == "impure" then (if value then "--impure" else "--pure") else "--arg${if (builtins.typeOf value) == "string" then "str" else ""} ${name} ${argValue value}";
                  configArgs = builtins.concatStringsSep " " (lib.attrsets.mapAttrsToList (k: v: buildArg { name = k; value = v; }) configuration);
                in
                ''${nixBuildPath} ${srcPath}/default.nix ${configArgs} ${buildArg { name = "cacheBreaker"; value = "$(echo \\\"$nixBuildExe\\\" | sha256sum -t | head -c5)${breaker}"; }}''
              );
              availableModeFlags = (builtins.filter (lib.strings.hasPrefix "use") (builtins.attrNames (lib.trivial.functionArgs evalTarget))) ++ ["impure"];
              configurations = lib.attrsets.cartesianProductOfSets (builtins.listToAttrs (map (modeFlag: { name = modeFlag; value = [false true]; }) availableModeFlags));
              sed = "${pkgs.gnused}/bin/sed";
              reportCommands = { metaProps }: map (configuration: builtins.traceVerbose "Generating report for ${builtins.toJSON configuration}" ''
                echo "Running case: ${writeAttemptOutPath "$nixBuildExe" "$src" configuration}"
                OUTPATH=$(${writeAttemptOutPath "$nixBuildExe" "$src" configuration} 2>/dev/null || echo "/failed")
                SUCCESS=false
                if [[ -d "$OUTPATH" && -f "$OUTPATH/helloworld.txt" || -d "$OUTPATH" && -f "$OUTPATH/hello.txt" ]]; then 
                  echo -e "    \033[32mSuccess: $OUTPATH\033[0m"
                  SUCCESS=true
                else
                  echo -e "    \033[0;31mFailed\033[0m"
                  SUCCESS=false
                fi
                write_json_if_needed ${lib.strings.escapeShellArg (builtins.toJSON (configuration // metaProps // { success = "SUCCESS_STATE"; }))}
              '') configurations;
              generator = pkgs.writeShellScript
                "gen-report.sh"
                ''
                  set -e
                  echo "Report of various configuration states:"
                  function write_json_if_needed()
                  {
                    if $SUCCESS; then
                      SUCCESS="true"
                    else
                      SUCCESS="false"
                    fi
                    if [ -z ''${NIX_VERSION+x} ]; then
                      NIX_VERSION=""
                    fi
                    if [ ! -z ''${REPORTOUT+x} ]; then
                      echo -n "  $1" \
                        | ${sed} "s/[\"']SUCCESS_STATE[\"']/$SUCCESS/" \
                        | ${sed} "s/NIX_VERSION/$NIX_VERSION/" \
                        >> "$REPORTOUT"
                    fi
                  }
                  function write_json_sep_if_needed()
                  {
                    if [ ! -z ''${REPORTOUT+x} ]; then
                      echo "," >> "$REPORTOUT"
                    fi
                  }
                  if [ -z ''${FULL_REPORT_MODE+x} ]; then
                    echo "[" > "$REPORTOUT"
                  fi
                  ${builtins.concatStringsSep "\nwrite_json_sep_if_needed\n" (reportCommands { metaProps = { "nixVersion" = "NIX_VERSION"; }; })}
                  if [ -z ''${FULL_REPORT_MODE+x} ]; then
                    echo -e "\n]" >> "$REPORTOUT"
                  fi
                '';
              runGeneratorFor = nixVersion: versionTitle: srcDirVar: ''
                export NIX_VERSION="${versionTitle}"
                NIX_HOME="${nixVersion}"
                echo -e "\nNix ${versionTitle} ($($NIX_HOME/bin/nix-build --version)) at $NIX_HOME:"
                GENERATOR_SCRIPT=$($NIX_HOME/bin/nix build .#report.generator --impure --show-trace --print-out-paths)
                src="${srcDirVar}" nixBuildExe="$NIX_HOME/bin/nix-build" $GENERATOR_SCRIPT | ${sed} "s/^/  /"
                echo -e "\n"
              '';
              fullReportGenerator = pkgs.writeShellScript
                "gen-full-report.sh"
                ''
                  set -eu
                  export SOURCE_DIR="${./.}"
                  echo "Source dir is $SOURCE_DIR"
                  export TEST_DIR=$(mktemp -d -t 'nixltstest' 2>/dev/null || mktemp -d 2>/dev/null)

                  echo "Copying test materials to $TEST_DIR"
                  bash -c "cp -R $SOURCE_DIR/* \"$TEST_DIR\""
                  chmod -R 770 "$TEST_DIR"

                  ls -al "$TEST_DIR"
                  cd "$TEST_DIR"

                  echo "Beginning tests..."

                  if [ ! -z ''${REPORTOUT+x} ]; then
                    echo -e "[\n" > "$REPORTOUT"
                  fi
                  export FULL_REPORT_MODE=true
                  ${runGeneratorFor nix-stable "Stable" "$TEST_DIR"}
                  if [ ! -z ''${REPORTOUT+x} ]; then
                    echo "," >> "$REPORTOUT"
                  fi
                  ${runGeneratorFor nix-lst "LST" "$TEST_DIR"}
                  if [ ! -z ''${REPORTOUT+x} ]; then
                    echo -e "\n]" >> "$REPORTOUT"
                    # Pretty-format the file to the format guessed by extension
                    "${"${pkgs.yq-go}/bin/yq"}" -i --indent 2 -M -P '.' --input-format json --output-format auto "$REPORTOUT"
                  fi


                  echo "You may wish to delete the content of "$TEST_DIR", if you do not want to rerun any of the above scenarios for logs."
                '';
            in {
              generator = generator; # Report generator
              inherit fullReportGenerator; # Report generator for both prior-correct and LST-failing cases
              inherit availableModeFlags; # Display with `nix eval .#report.availableModeFlags`
              inherit configurations; # Display pretty output with `nix eval .#report.configurations --json | nix-shell -p yq --command yq`
            }
          );
        }
      );
}
