# hacker-flake

just compile some shit.

## quick

```bash
# compile
nix run github:weyl-ai/hacker-flake -- main.cpp -o app

# debug (pwndbg)
nix run github:weyl-ai/hacker-flake#debug -- ./app

# shell
nix shell github:weyl-ai/hacker-flake
```

## shells

```bash
nix shell github:weyl-ai/hacker-flake         # C++
nix shell github:weyl-ai/hacker-flake#cuda    # CUDA
nix shell github:weyl-ai/hacker-flake#static  # musl static
```

## new project

```bash
nix flake init -t github:weyl-ai/hacker-flake
nix develop
hacker main.cpp -o app
./app
```

## flags

```
-O2                      optimize
-g3 -gdwarf-5            full symbols
-std=c++23               modern
-fno-omit-frame-pointer  stack traces
no hardening             predictable
no strip                 symbols stay
```

## stdenvs

for nix derivations:

```nix
pkgs.hacker-stdenv.mkDerivation { ... }        # glibc
pkgs.hacker-stdenv-static.mkDerivation { ... } # musl static
pkgs.hacker-stdenv-cuda.mkDerivation { ... }   # cuda
```

## pwndbg

debug uses pwndbg. context, heap analysis, the works.

```bash
hacker-debug ./app
pwndbg> break main
pwndbg> run
pwndbg> context
```

---

b7r6 — idea  
claude — execution
