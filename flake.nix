{
  description = "hacker-flake — just compile some shit";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nvchad.url = "github:nix-community/nix4nvchad";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nvchad, treefmt-nix }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        inherit system;
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [
            self.overlays.default
            (final: prev: {
              nvchad = nvchad.packages.${system}.nvchad;
            })
          ];
        };
      });

      treefmtEval = forAllSystems ({ pkgs, system, ... }:
        treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs.nixpkgs-fmt.enable = true;
          programs.clang-format.enable = true;
          programs.clang-format.includes = [ "*.c" "*.h" "*.cpp" "*.cu" "*.cuh" ];
          programs.shfmt.enable = true;
        }
      );
    in
    {
      # ══════════════════════════════════════════════════════════════════════
      # OVERLAYS
      # ══════════════════════════════════════════════════════════════════════

      overlays.default = import ./nix/overlay.nix;

      # ══════════════════════════════════════════════════════════════════════
      # APPS
      # ══════════════════════════════════════════════════════════════════════

      apps = forAllSystems ({ pkgs, system, ... }: {
        # nix run github:weyl-ai/hacker-flake -- main.cpp -o app
        default = {
          type = "app";
          program = "${pkgs.hacker-compile}/bin/hacker";
        };

        # nix run github:weyl-ai/hacker-flake#debug -- ./app
        debug = {
          type = "app";
          program = "${pkgs.hacker-debug}/bin/hacker-debug";
        };

        # nix run github:weyl-ai/hacker-flake#nvim
        nvim = {
          type = "app";
          program = "${pkgs.hacker-nvim}/bin/hacker-nvim";
        };
      });

      # ══════════════════════════════════════════════════════════════════════
      # PACKAGES
      # ══════════════════════════════════════════════════════════════════════

      packages = forAllSystems ({ pkgs, ... }: {
        default = pkgs.hacker-compile;

        inherit (pkgs)
          hacker-compile
          hacker-debug
          hacker-run
          hacker-nvim
          hacker-clang
          ;
      });

      # ══════════════════════════════════════════════════════════════════════
      # DEV SHELLS
      # ══════════════════════════════════════════════════════════════════════

      devShells = forAllSystems ({ pkgs, ... }: {
        # nix shell github:weyl-ai/hacker-flake
        default = pkgs.hacker-shell-cuda;

        # nix shell github:weyl-ai/hacker-flake#cpp
        cpp = pkgs.hacker-shell-cpp;

        # nix shell github:weyl-ai/hacker-flake#cuda
        cuda = pkgs.hacker-shell-cuda;

        # nix shell github:weyl-ai/hacker-flake#static
        static = pkgs.hacker-shell-static;
      });

      # ══════════════════════════════════════════════════════════════════════
      # TEMPLATES
      # ══════════════════════════════════════════════════════════════════════

      templates = {
        # nix flake init -t github:weyl-ai/hacker-flake
        default = {
          path = ./templates/default;
          description = "C++ project with hacker-flake";
        };

        cuda = {
          path = ./templates/cuda;
          description = "CUDA project with hacker-flake";
        };
      };

      # ══════════════════════════════════════════════════════════════════════
      # FORMATTER
      # ══════════════════════════════════════════════════════════════════════

      # nix fmt
      formatter = forAllSystems ({ system, ... }: treefmtEval.${system}.config.build.wrapper);
    };
}
