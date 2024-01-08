{
  description = "Package for Meteor, the JavaScript App Platform.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      formatter = pkgs.alejandra;
      packages = {
        default = self.packages.${system}.meteor;
        meteor = let
          version = "2.14";
          sourceUrls = {
            x86_64-linux = pkgs.fetchurl {
              url = "https://static.meteor.com/packages-bootstrap/${version}/meteor-bootstrap-os.linux.x86_64.tar.gz";
              sha256 = "sha256-t8IufLtSPNVZ7aPiQcRlTvY+zyJvCBZllcGx3IHCV3I=";
            };
            x86_64-darwin = pkgs.fetchurl {
              url = "https://static.meteor.com/packages-bootstrap/${version}/meteor-bootstrap-os.osx.x86_64.tar.gz";
              sha256 = "sha256-Wu62DCO4hkaP0Wfz8yK6txbeUiLrdYWfcZYhySXbE/Q=";
            };
            aarch64-darwin = pkgs.fetchurl {
              url = "https://static.meteor.com/packages-bootstrap/${version}/meteor-bootstrap-os.osx.arm64.tar.gz";
              sha256 = "sha256-uGEc3/GiRBZg/z6P8f7iOyfELlPU2Kntu2x+RPRjwTU=";
            };
          };
        in
          pkgs.stdenv.mkDerivation {
            inherit version;
            pname = "meteor";

            src = sourceUrls.${system};

            sourceRoot = ".meteor";

            installPhase = ''
              mkdir $out

              cp -r packages $out
              chmod -R +w $out/packages

              cp -r package-metadata $out

              devBundle=$(find $out/packages/meteor-tool -name dev_bundle)
              ln -s $devBundle $out/dev_bundle

              toolsDir=$(dirname $(find $out/packages -print | grep "meteor-tool/.*/tools/index.js$"))
              ln -s $toolsDir $out/tools

              # Meteor needs an initial package-metadata in $HOME/.meteor,
              # otherwise it fails spectacularly.
              mkdir -p $out/bin
              cat << EOF > $out/bin/meteor
              #!${pkgs.runtimeShell}

              if [[ ! -f \$HOME/.meteor/package-metadata/v2.0.1/packages.data.db ]]; then
                mkdir -p \$HOME/.meteor/package-metadata/v2.0.1
                cp $out/package-metadata/v2.0.1/packages.data.db "\$HOME/.meteor/package-metadata/v2.0.1"
                chown "\$(whoami)" "\$HOME/.meteor/package-metadata/v2.0.1/packages.data.db"
                chmod +w "\$HOME/.meteor/package-metadata/v2.0.1/packages.data.db"
              fi

              $out/dev_bundle/bin/node --no-wasm-code-gc \''${TOOL_NODE_FLAGS} $out/tools/index.js "\$@"
              EOF
              chmod +x $out/bin/meteor
            '';

            postFixup = pkgs.lib.optionalString pkgs.stdenv.isLinux ''
              # Patch Meteor to dynamically fixup shebangs and ELF metadata where
              # necessary.
              pushd $out
              patch -p1 < ${./main.patch}
              popd
              substituteInPlace $out/tools/cli/main.js \
                --replace "@INTERPRETER@" "$(cat $NIX_CC/nix-support/dynamic-linker)" \
                --replace "@RPATH@" "${
                pkgs.lib.makeLibraryPath [
                  pkgs.stdenv.cc.cc
                  pkgs.zlib
                  pkgs.curl
                  pkgs.xz
                ]
              }" \
                --replace "@PATCHELF@" "${pkgs.patchelf}/bin/patchelf"

              # Patch node.
              patchelf \
                --set-interpreter $(cat $NIX_CC/nix-support/dynamic-linker) \
                --set-rpath "$(patchelf --print-rpath $out/dev_bundle/bin/node):${pkgs.stdenv.cc.cc.lib}/lib" \
                $out/dev_bundle/bin/node

              # Patch mongo.
              for p in $out/dev_bundle/mongodb/bin/mongo{d,s}; do
                patchelf \
                  --set-interpreter $(cat $NIX_CC/nix-support/dynamic-linker) \
                  --set-rpath "$(patchelf --print-rpath $p):${
                pkgs.lib.makeLibraryPath [
                  pkgs.stdenv.cc.cc
                  pkgs.zlib
                  pkgs.curl
                  pkgs.xz
                ]
              }" \
                  $p
              done

              # Patch node dlls.
              for p in $(find $out/packages -name '*.node'); do
                patchelf \
                  --set-rpath "$(patchelf --print-rpath $p):${pkgs.stdenv.cc.cc.lib}/lib" \
                  $p || true
              done
            '';

            meta = with pkgs.lib; {
              description = "Meteor is an ultra-simple environment for building modern web applications.";
              homepage = "https://www.meteor.com/";
              platforms = builtins.attrNames sourceUrls;
              maintainers = with maintainers; [michaelshmitty];
              mainProgram = "meteor";
            };
          };
      };

      overlays.default = final: prev: {
        inherit (self.packages.${prev.system}) meteor;
      };
    });
}
