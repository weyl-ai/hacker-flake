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
        config.allowUnfree = true;
        config.cudaSupport = true;
        overlays = [ hacker.overlays.default ];
      };
    in
    {
      devShells.${system}.default = pkgs.hacker-shell-cuda;

      packages.${system}.default = pkgs.hacker-stdenv-cuda.mkDerivation {
        name = "kernel";
        src = ./.;
        buildPhase = "$CXX -o kernel main.cu -lcudart";
        installPhase = "mkdir -p $out/bin; cp kernel $out/bin/";
      };
    };
}
