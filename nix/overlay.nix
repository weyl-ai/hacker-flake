# overlay.nix — hacker-flake overlay
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# An overlay is a pure function from the world as it is to the world as it ought to be.
#
# O2, full symbols, no hardening, gdb works.
# just compile some shit.
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

final: _prev:
let
  inherit (final) lib stdenv;

  # ════════════════════════════════════════════════════════════════════════
  # PLATFORM
  # ════════════════════════════════════════════════════════════════════════

  host-platform = stdenv.hostPlatform;

  is-x86-64 = host-platform.isx86_64;
  is-aarch64 = host-platform.isAarch64;

  target-triple =
    host-platform.config or (
      if is-x86-64 then
        "x86_64-unknown-linux-gnu"
      else if is-aarch64 then
        "aarch64-unknown-linux-gnu"
      else
        throw "weyl-std: unsupported platform ${host-platform.system}"
    );

  # ════════════════════════════════════════════════════════════════════════
  # GCC PATHS
  # ════════════════════════════════════════════════════════════════════════

  gcc-version = "${lib.versions.majorMinor final.gcc15.version}.0";

  gcc-paths = {
    include = "${final.gcc15.cc}/include/c++/${gcc-version}";
    include-arch = "${final.gcc15.cc}/include/c++/${gcc-version}/${target-triple}";
    lib = "${final.gcc15.cc}/lib/gcc/${target-triple}/${gcc-version}";
  };

  # ════════════════════════════════════════════════════════════════════════
  # THE FLAGS
  # ════════════════════════════════════════════════════════════════════════
  #
  # These are not suggestions. These are the standard.
  #
  # O2: Real performance. O0 and Og are for toys.
  # g3: Maximum debug info. Macros included.
  # dwarf-5: Modern format. Best tooling support.
  # frame-pointers: Stack traces work. Always.
  # no-hardening: Predictable addresses. No overhead. No theater.

  # Optimization: fast code that debugs
  opt-flags = "-O2";

  # Debug: everything visible
  debug-flags = lib.concatStringsSep " " [
    "-g3" # maximum info (includes macros)
    "-gdwarf-5" # modern dwarf format
    "-fno-limit-debug-info" # don't truncate for speed
    "-fstandalone-debug" # full info for system headers
  ];

  # Frame pointers: stack traces work
  frame-flags = lib.concatStringsSep " " [
    "-fno-omit-frame-pointer" # keep rbp/x29
    "-mno-omit-leaf-frame-pointer" # even in leaves
  ];

  # Kill hardening: no theater
  no-harden-flags = lib.concatStringsSep " " (
    [
      "-U_FORTIFY_SOURCE" # remove buffer "protection"
      "-D_FORTIFY_SOURCE=0" # really remove it
      "-fno-stack-protector" # no canaries
      "-fno-stack-clash-protection" # no stack clash
    ]
    ++ lib.optional is-x86-64 "-fcf-protection=none"
  ); # no CET

  # Combined: the weyl standard
  weyl-cflags = lib.concatStringsSep " " [
    opt-flags
    debug-flags
    frame-flags
    no-harden-flags
  ];

  # ════════════════════════════════════════════════════════════════════════
  # DERIVATION ATTRIBUTES
  # ════════════════════════════════════════════════════════════════════════

  weyl-attrs = {
    dontStrip = true; # symbols stay
    separateDebugInfo = false; # debug info in binary
    hardeningDisable = [ "all" ]; # kill nix wrapper hardening
    noAuditTmpdir = true; # don't check /tmp
  };

  # ════════════════════════════════════════════════════════════════════════
  # CLANG WRAPPERS
  # ════════════════════════════════════════════════════════════════════════

  # Extract clang from llvmPackages
  unwrapped-clang = final.llvmPackages.clang.cc or final.llvmPackages.clang;

  # Check for libc++
  has-libcxx = final.llvmPackages ? libcxx && final.llvmPackages.libcxx != null;

  # Clang + gcc libstdc++ (for glibc)
  clang-glibc = final.wrapCCWith {
    cc = unwrapped-clang;
    useCcForLibs = true;
    gccForLibs = final.gcc15.cc;
  };

  # Clang + musl + gcc libstdc++ (libc++ has musl compatibility issues)
  # Use pkgsMusl.gcc15 for musl-aware libstdc++
  musl-gcc = final.pkgsMusl.gcc15 or final.gcc15;

  musl-target-triple =
    if is-x86-64 then
      "x86_64-unknown-linux-musl"
    else if is-aarch64 then
      "aarch64-unknown-linux-musl"
    else
      throw "weyl-std-musl: unsupported platform ${host-platform.system}";

  musl-gcc-version = "${lib.versions.majorMinor musl-gcc.version}.0";

  musl-gcc-paths = {
    include = "${musl-gcc.cc}/include/c++/${musl-gcc-version}";
    include-arch = "${musl-gcc.cc}/include/c++/${musl-gcc-version}/${musl-target-triple}";
    lib = "${musl-gcc.cc}/lib/gcc/${musl-target-triple}/${musl-gcc-version}";
  };

  clang-musl = final.wrapCCWith {
    cc = unwrapped-clang;
    libc = final.musl;
    bintools = final.wrapBintoolsWith {
      bintools = final.binutils-unwrapped;
      libc = final.musl;
    };

    useCcForLibs = true;
    gccForLibs = musl-gcc.cc;
  };

  # ════════════════════════════════════════════════════════════════════════
  # STDENV FACTORY
  # ════════════════════════════════════════════════════════════════════════

  mk-weyl-stdenv =
    { name
    , base
    , cflags
    , ldflags
    , cxxstd ? "-std=c++23"
    , extra ? { }
    ,
    }:

    let
      enhanced = final.stdenvAdapters.addAttrsToDerivation
        (
          weyl-attrs
          // {
            NIX_CFLAGS_COMPILE = cflags;
            NIX_LDFLAGS = ldflags;
            NIX_CXXSTDLIB_COMPILE = cxxstd;
          }
          // extra
        )
        base;
    in
    enhanced
    // {
      passthru = (enhanced.passthru or { }) // {
        weyl = {
          inherit
            name
            cflags
            ldflags
            cxxstd
            ;

          target = target-triple;
          version = "1.0.0";
        };
      };
    };

  # ════════════════════════════════════════════════════════════════════════
  # GLIBC CONFIGURATION
  # ════════════════════════════════════════════════════════════════════════

  glibc-cflags = lib.concatStringsSep " " [
    "-I${gcc-paths.include}"
    "-I${gcc-paths.include-arch}"
    "-I${final.glibc.dev}/include"
    "-B${final.glibc}/lib"
    "-B${gcc-paths.lib}"

    weyl-cflags
  ];

  glibc-ldflags = lib.concatStringsSep " " [
    "-L${gcc-paths.lib}"
    "-L${final.gcc15}/lib"
    "-L${final.glibc}/lib"
  ];

  glibc-static-cflags = lib.concatStringsSep " " [
    "-I${gcc-paths.include}"
    "-I${gcc-paths.include-arch}"
    "-I${final.glibc.dev}/include"
    "-B${final.glibc.static}/lib"
    "-B${gcc-paths.lib}"
    "-static-libgcc"
    "-static-libstdc++"

    weyl-cflags
  ];

  glibc-static-ldflags = lib.concatStringsSep " " [
    "-static"
    "-L${gcc-paths.lib}"
    "-L${final.gcc15}/lib"
    "-L${final.glibc.static}/lib"
  ];

  # ════════════════════════════════════════════════════════════════════════
  # MUSL CONFIGURATION
  # ════════════════════════════════════════════════════════════════════════

  musl-cflags = lib.concatStringsSep " " [
    "-I${musl-gcc-paths.include}"
    "-I${musl-gcc-paths.include-arch}"
    "-I${final.musl.dev}/include"
    "-B${final.musl}/lib"
    "-B${musl-gcc-paths.lib}"

    weyl-cflags
  ];

  musl-ldflags = lib.concatStringsSep " " [
    "-L${musl-gcc-paths.lib}"
    "-L${musl-gcc}/lib"
    "-L${final.musl}/lib"
  ];

  musl-static-cflags = lib.concatStringsSep " " [
    "-I${musl-gcc-paths.include}"
    "-I${musl-gcc-paths.include-arch}"
    "-I${final.musl.dev}/include"
    "-B${musl-gcc-paths.lib}"
    "-static-libgcc"
    "-static-libstdc++"

    weyl-cflags
  ];

  musl-static-ldflags = lib.concatStringsSep " " [
    "-static"
    "-L${musl-gcc-paths.lib}"
    "-L${musl-gcc}/lib"
    "-L${final.musl}/lib"
  ];

  musl-cxxstd = "-std=c++23";

  # ════════════════════════════════════════════════════════════════════════
  # CUDA CONFIGURATION
  # ════════════════════════════════════════════════════════════════════════

  # CUDA merged path (if available)
  cuda-merged = final.cuda-merged or final.cudaPackages.cudatoolkit or null;
  has-cuda = cuda-merged != null;

  cuda-arch = if is-aarch64 then "sm_90a" else "sm_120"; # Grace vs Blackwell

  cuda-cflags = lib.optionalString has-cuda (
    lib.concatStringsSep " " [
      "-std=c++23"
      "-I${gcc-paths.include}"
      "-I${gcc-paths.include-arch}"
      "-I${final.glibc.dev}/include"
      "--cuda-path=${cuda-merged}"
      "--cuda-gpu-arch=${cuda-arch}"
      "-B${final.glibc}/lib"
      "-B${gcc-paths.lib}"
      "-include ${./cuda-gcc15-compat.h}"

      # Suppress CUDA + GCC 15 compatibility noise
      "-Wno-inline-namespace-reopened-noninline"
      "-Wno-unknown-attributes"
      "-Wno-unknown-warning-option"
      "-Wno-deprecated-builtins"
      "-Wno-user-defined-literals"

      weyl-cflags
    ]
  );

  cuda-ldflags = lib.optionalString has-cuda (
    lib.concatStringsSep " " [
      "-L${gcc-paths.lib}"
      "-L${final.gcc15}/lib"
      "-L${final.gcc15.cc.lib}/lib"
      "-L${final.glibc}/lib"
      "-L${cuda-merged}/lib64"
      "-L${cuda-merged}/lib"
      "-lcudart"
      "-lstdc++"
    ]
  );

in
{
  # ════════════════════════════════════════════════════════════════════════
  # EXPORTED STDENVS
  # ════════════════════════════════════════════════════════════════════════

  # Host development: glibc + clang + C++23
  weyl-stdenv = mk-weyl-stdenv {
    name = "weyl-stdenv";
    base = final.stdenvAdapters.overrideCC final.gcc15Stdenv clang-glibc;
    cflags = glibc-cflags;
    ldflags = glibc-ldflags;
  };

  # Static binaries: glibc static
  weyl-stdenv-static = mk-weyl-stdenv {
    name = "weyl-stdenv-static";
    base = final.stdenvAdapters.overrideCC final.gcc15Stdenv clang-glibc;
    cflags = glibc-static-cflags;
    ldflags = glibc-static-ldflags;
  };

  # Portable binaries: musl + libc++
  weyl-stdenv-musl = mk-weyl-stdenv {
    name = "weyl-stdenv-musl";
    base = final.stdenvAdapters.overrideCC final.stdenv clang-musl;
    cflags = musl-cflags;
    ldflags = musl-ldflags;
    cxxstd = musl-cxxstd;
  };

  # Fully static: musl static (deploy anywhere)
  weyl-stdenv-musl-static = mk-weyl-stdenv {
    name = "weyl-stdenv-musl-static";
    base = final.stdenvAdapters.overrideCC final.stdenv clang-musl;
    cflags = musl-static-cflags;
    ldflags = musl-static-ldflags;
    cxxstd = musl-cxxstd;
  };

  # CUDA development: device + host compilation
  weyl-stdenv-cuda = lib.mkIf has-cuda (mk-weyl-stdenv {
    name = "weyl-stdenv-cuda";
    base = final.stdenvAdapters.overrideCC final.gcc15Stdenv clang-glibc;
    cflags = cuda-cflags;
    ldflags = cuda-ldflags;
    extra = {
      CUDA_HOME = cuda-merged;
      CUDA_PATH = cuda-merged;
    };
  });

  # ════════════════════════════════════════════════════════════════════════
  # WRAPPED CLANG
  # ════════════════════════════════════════════════════════════════════════

  hacker-clang = final.writeShellScriptBin "clang++" ''
    exec ${clang-glibc}/bin/clang++ \
      ${weyl-cflags} -std=c++23 \
      -I${gcc-paths.include} \
      -I${gcc-paths.include-arch} \
      "$@"
  '';

  hacker-clang-static = final.writeShellScriptBin "clang++-static" ''
    exec ${clang-musl}/bin/clang++ \
      ${weyl-cflags} -std=c++23 \
      -I${musl-gcc-paths.include} \
      -I${musl-gcc-paths.include-arch} \
      -static-libgcc -static-libstdc++ -static \
      "$@"
  '';

  # ════════════════════════════════════════════════════════════════════════
  # CUDA SETUP HOOK
  # ════════════════════════════════════════════════════════════════════════

  hacker-cuda-hook = final.makeSetupHook
    {
      name = "hacker-cuda-hook";
    }
    (final.writeScript "hacker-cuda-hook.sh" ''
      # Set up CUDA runtime library path (NixOS)
      export LD_LIBRARY_PATH="/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    '');

  # ════════════════════════════════════════════════════════════════════════
  # COMPILE APP
  # ════════════════════════════════════════════════════════════════════════

  hacker-compile = final.writeShellScriptBin "hacker" ''
    set -e

    if [ $# -eq 0 ]; then
      echo "hacker — just compile some shit"
      echo ""
      echo "usage: hacker <file.cpp> [-o output] [flags...]"
      echo "       hacker <file.cu>  [-o output] [flags...]"
      echo ""
      echo "flags baked in:"
      echo "  -O2 -g3 -gdwarf-5 -std=c++23"
      echo "  -fno-omit-frame-pointer"
      echo "  no hardening, no strip"
      exit 0
    fi

    src="$1"
    shift

    case "$src" in
      *.cu)
        ${if has-cuda then ''
          exec ${unwrapped-clang}/bin/clang++ \
            ${cuda-cflags} \
            ${cuda-ldflags} \
            "$src" "$@"
        '' else ''
          echo "CUDA not available on this platform"
          exit 1
        ''}
        ;;
      *.cpp|*.cc|*.cxx|*.c++)
        exec ${clang-glibc}/bin/clang++ \
          ${weyl-cflags} -std=c++23 \
          -I${gcc-paths.include} \
          -I${gcc-paths.include-arch} \
          "$src" "$@"
        ;;
      *.c)
        exec ${clang-glibc}/bin/clang \
          ${weyl-cflags} \
          "$src" "$@"
        ;;
      *)
        echo "unknown file type: $src"
        exit 1
        ;;
    esac
  '';

  # ════════════════════════════════════════════════════════════════════════
  # NVIM WITH CUDA ENVIRONMENT
  # ════════════════════════════════════════════════════════════════════════

  hacker-nvim = final.writeShellScriptBin "hacker-nvim" ''
    # Set up CUDA runtime library path
    export LD_LIBRARY_PATH="/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

    # Set up CUDA environment
    ${lib.optionalString has-cuda ''
      export CUDA_HOME="${cuda-merged}"
      export CUDA_PATH="${cuda-merged}"
      export PATH="${cuda-merged}/bin''${PATH:+:$PATH}"
    ''}

    # Run nvchad
    exec ${final.nvchad}/bin/nvim "$@"
  '';

  # ════════════════════════════════════════════════════════════════════════
  # DEBUG APP (pwndbg)
  # ════════════════════════════════════════════════════════════════════════

  hacker-debug = final.writeShellScriptBin "hacker-debug" ''
    if [ $# -eq 0 ]; then
      echo "usage: hacker-debug <executable> [args...]"
      exit 1
    fi

    # Set up CUDA runtime library path for debugging CUDA binaries
    export LD_LIBRARY_PATH="/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

    exec ${final.gdb}/bin/gdb "$@"
  '';

  # ════════════════════════════════════════════════════════════════════════
  # CUDA RUN WRAPPER
  # ════════════════════════════════════════════════════════════════════════

  hacker-run = final.writeShellScriptBin "hacker-run" ''
    if [ $# -eq 0 ]; then
      echo "hacker-run — run CUDA binaries with driver library path"
      echo ""
      echo "usage: hacker-run <executable> [args...]"
      exit 1
    fi

    # Set up CUDA runtime library path (NixOS)
    export LD_LIBRARY_PATH="/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

    exec "$@"
  '';

  # ════════════════════════════════════════════════════════════════════════
  # CROSS-COMPILATION
  # ════════════════════════════════════════════════════════════════════════
  #
  # Usage:
  #   pkgs.weyl-cross.grace.mkDerivation { ... }
  #   pkgs.weyl-cross.jetson.mkDerivation { ... }

  weyl-cross =
    lib.optionalAttrs is-x86-64
      {
        # Grace Hopper: aarch64 + Hopper GPU
        grace = rec {
          name = "grace";
          arch = "aarch64";
          gpu = "sm_90a";
          pkgs = final.pkgsCross.aarch64-multiplatform;
          mkDerivation =
            args:
            pkgs.stdenv.mkDerivation (
              args
              // weyl-attrs
              // {
                NIX_CFLAGS_COMPILE = (args.NIX_CFLAGS_COMPILE or "") + " " + weyl-cflags;
                passthru = (args.passthru or { }) // {
                  weyl-target = name;
                };
              }
            );
        };

        # Jetson Orin: aarch64 + Ampere GPU
        jetson = rec {
          name = "jetson";
          arch = "aarch64";
          gpu = "sm_87";
          pkgs = final.pkgsCross.aarch64-multiplatform;
          mkDerivation =
            args:
            pkgs.stdenv.mkDerivation (
              args
              // weyl-attrs
              // {
                NIX_CFLAGS_COMPILE = (args.NIX_CFLAGS_COMPILE or "") + " " + weyl-cflags;
                passthru = (args.passthru or { }) // {
                  weyl-target = name;
                };
              }
            );
        };

        # Generic aarch64: no GPU
        aarch64 = rec {
          name = "aarch64";
          arch = "aarch64";
          gpu = null;
          pkgs = final.pkgsCross.aarch64-multiplatform;
          mkDerivation =
            args:
            pkgs.stdenv.mkDerivation (
              args
              // weyl-attrs
              // {
                NIX_CFLAGS_COMPILE = (args.NIX_CFLAGS_COMPILE or "") + " " + weyl-cflags;
                passthru = (args.passthru or { }) // {
                  weyl-target = name;
                };
              }
            );
        };
      }
    // lib.optionalAttrs is-aarch64 {
      # Reverse: aarch64 → x86_64
      x86-64 = rec {
        name = "x86-64";
        arch = "x86_64";
        gpu = "sm_120";
        pkgs = final.pkgsCross.gnu64;

        mkDerivation =
          args:
          pkgs.stdenv.mkDerivation (
            args
            // weyl-attrs
            // {
              NIX_CFLAGS_COMPILE = (args.NIX_CFLAGS_COMPILE or "") + " " + weyl-cflags;
              passthru = (args.passthru or { }) // {
                weyl-target = name;
              };
            }
          );
      };
    };

  # ════════════════════════════════════════════════════════════════════════
  # HACKER-FLAKE COMPATIBILITY
  # ════════════════════════════════════════════════════════════════════════

  # Stdenv aliases
  hacker-stdenv = final.weyl-stdenv;
  hacker-stdenv-cuda = final.weyl-stdenv-cuda;
  hacker-stdenv-static = final.weyl-stdenv-static;

  # Shells
  hacker-shell-cpp = final.mkShell {
    name = "hacker-cpp";
    packages = [
      final.hacker-compile
      final.hacker-debug
      final.hacker-clang
      final.gdb
      final.lldb
      final.valgrind
      final.binutils
      final.cmake
      final.ninja
      final.pkg-config
    ];
    shellHook = ''
      echo "━━━ hacker-flake ━━━"
      echo "O2 | g3 | DWARF-5 | C++23 | gdb"
      echo ""
      echo "  hacker main.cpp -o app    compile"
      echo "  hacker-debug ./app        debug"
      echo "  clang++ ...               raw (with flags)"
      echo ""
    '';
  };

  hacker-shell-cuda =
    if has-cuda then
      (final.mkShell {
        name = "hacker-cuda";
        packages = [
          final.hacker-compile
          final.hacker-debug
          final.hacker-run
          final.cmake
          final.ninja
          final.pkg-config
          final.gdb
          final.lldb
          final.rr
          final.valgrind
          final.binutils
          final.linuxPackages.nvidia_x11
          final.nvtopPackages.nvidia
          final.nvchad
          cuda-merged
          final.hacker-cuda-hook
        ];
        CUDA_HOME = cuda-merged;
        CUDA_PATH = cuda-merged;
        LD_LIBRARY_PATH = "/run/opengl-driver/lib:/usr/lib/cuda/lib64:${cuda-merged}/lib64:${cuda-merged}/lib";
        shellHook = ''
          echo "━━━ hacker-flake/cuda ━━━"
          echo "O2 | g3 | DWARF-5 | C++23 | ${cuda-arch}"
          echo "gdb | lldb | rr | valgrind | nvidia-smi | nvtop | nvim"
          echo ""
          echo "  hacker kernel.cu -o app   compile"
          echo "  hacker-run ./app          run with GPU driver"
          echo "  hacker-debug ./app        debug"
          echo "  nvidia-smi                GPU status"
          echo "  nvtop                     GPU monitor"
          echo ""
        '';
      }) else
      (final.mkShell {
        name = "hacker-cuda-unavailable";
        shellHook = ''
          echo "CUDA is not available on this platform"
          exit 1
        '';
      });

  hacker-shell-static = final.mkShell {
    name = "hacker-static";
    packages = [
      final.hacker-clang-static
      final.hacker-debug
      final.gdb
      final.binutils
    ];
    shellHook = ''
      echo "━━━ hacker-flake/static ━━━"
      echo "musl | static | deploy anywhere"
      echo ""
      echo "  clang++-static main.cpp -o app"
      echo ""
    '';
  };

  # ════════════════════════════════════════════════════════════════════════
  # INTROSPECTION
  # ════════════════════════════════════════════════════════════════════════

  weyl-stdenv-info = {
    version = "1.0.0";
    target = target-triple;
    inherit gcc-version;
    optimization = "O2";
    debug = "g3 + DWARF5";
    frame-pointers = "always";
    hardening = "disabled";
    cflags = weyl-cflags;
    inherit has-cuda;
    inherit has-libcxx;
    cross-targets =
      if is-x86-64 then
        [
          "grace"
          "jetson"
          "aarch64"
        ]
      else
        [ "x86-64" ];
  };
}
