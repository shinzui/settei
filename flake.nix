{
  description = "settei";

  inputs = {
    haskell-nix-dev.url = "github:shinzui/haskell-nix-dev";
    nixpkgs.follows = "haskell-nix-dev/nixpkgs";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    treefmt-nix.follows = "haskell-nix-dev/treefmt-nix";

    # nixpkgs' GHC 9.12 package set currently predates parserOptionGroup. Keep the
    # command-line adapter on the registered and source-inspected 0.19.0.0 API.
    optparse-applicative = {
      url = "https://hackage.haskell.org/package/optparse-applicative-0.19.0.0/optparse-applicative-0.19.0.0.tar.gz";
      flake = false;
    };

    # Mori's registered source corpus currently carries kdl-hs 1.0.1. Pin the
    # Nix build to that source-inspected API instead of nixpkgs' newer 1.1.0.
    kdl-hs = {
      url = "https://hackage.haskell.org/package/kdl-hs-1.0.1/kdl-hs-1.0.1.tar.gz";
      flake = false;
    };

    pre-commit-hooks.url = "github:cachix/git-hooks.nix";
    pre-commit-hooks.inputs.nixpkgs.follows = "nixpkgs";
  };

  # The haskell-nix-dev base flake's binary cache, so the first `nix develop` downloads
  # prebuilt GHC/HLS/cabal instead of compiling HLS from source. nixConfig is only honored
  # for users who trust this flake; for a guaranteed pull run `cachix use shinzui` once, or
  # add these two lines to your nix.conf.
  nixConfig = {
    extra-substituters = [ "https://shinzui.cachix.org" ];
    extra-trusted-public-keys = [ "shinzui.cachix.org-1:QEmAoJrA9WwLP0uxfDgktLi2BRrcvQQWdz8NzcMg4/E=" ];
  };

  # This flake is a thin, seihou-managed shell. All project wiring lives in the
  # imported modules under ./nix, and your own customizations belong in an
  # (optional, unmanaged) ./flake.module.nix — see flake.module.nix.example.
  outputs = inputs@{ flake-parts, nixpkgs, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nixpkgs.lib.systems.flakeExposed;

      imports =
        [
          ./nix/haskell.nix
          ./nix/treefmt.nix
          ./nix/pre-commit.nix
        ]
        # Your project-specific customizations. seihou never generates, touches,
        # or migrates this file, so it is the conflict-free place to extend.
        ++ nixpkgs.lib.optional (builtins.pathExists ./flake.module.nix) ./flake.module.nix;
    };
}
