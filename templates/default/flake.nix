{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    hacker.url = "github:weyl-ai/hacker-flake";
  };

  outputs = { nixpkgs, hacker, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ hacker.overlays.default ];
      };
    in
    {
      devShells.${system}.default = pkgs.hacker-shell-cpp;

      packages.${system}.default = pkgs.hacker-stdenv.mkDerivation {
        name = "app";
        src = ./.;
        buildPhase = "$CXX -o app main.cpp";
        installPhase = "mkdir -p $out/bin; cp app $out/bin/";
      };
    };
}
