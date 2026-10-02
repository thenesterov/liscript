{
  description = "Liscript Development Environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";

    isocline-src = {
      url = "github:daanx/isocline";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, isocline-src }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            zig
          ];

          shellHook = ''
            export ISOCLINE_SRC="${isocline-src}"
          '';
        };
      }
    );
}

