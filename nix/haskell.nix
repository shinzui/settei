# Haskell project wiring: dev shells (via the haskell-nix-dev base flake) and the
# project package (via callCabal2nix). seihou-managed — to add project-specific
# dev tools without editing this file, set `haskellProject.extraDevPackages` from
# ./flake.module.nix (see flake.module.nix.example).
{ inputs, lib, flake-parts-lib, ... }:
{
  options.perSystem = flake-parts-lib.mkPerSystemOption ({ ... }: {
    options.haskellProject.extraDevPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.ghciwatch pkgs.haskellPackages.hpack ]";
      description = ''
        Extra packages to add to the dev shell. Set this from ./flake.module.nix
        to add project-specific tooling without editing the generated
        ./nix/haskell.nix.
      '';
    };
  });

  config.perSystem = { system, pkgs, config, ... }:
    let
      hsdev = inputs.haskell-nix-dev.lib.${system};
      haskellPackages = pkgs.haskell.packages."ghc9124";

      optparseApplicativePackage =
        haskellPackages.callCabal2nix "optparse-applicative" inputs.optparse-applicative { };
      dhallPackage = haskellPackages.dhall.override {
        optparse-applicative = optparseApplicativePackage;
      };
      dhallJsonPackage = pkgs.haskell.lib.dontCheck (
        haskellPackages.dhall-json.override {
          dhall = dhallPackage;
          optparse-applicative = optparseApplicativePackage;
        }
      );
      kdlHsPackage = haskellPackages.callCabal2nix "kdl-hs" inputs.kdl-hs { };
      setteiPackage = haskellPackages.callCabal2nix "settei" ../settei { };
      setteiEnvPackage =
        haskellPackages.callCabal2nix "settei-env" ../settei-env {
          settei = setteiPackage;
        };
      setteiYamlPackage =
        haskellPackages.callCabal2nix "settei-yaml" ../settei-yaml {
          settei = setteiPackage;
        };
      setteiKdlPackage =
        haskellPackages.callCabal2nix "settei-kdl" ../settei-kdl {
          kdl-hs = kdlHsPackage;
          settei = setteiPackage;
        };
      setteiKubernetesPackage =
        haskellPackages.callCabal2nix "settei-kubernetes" ../settei-kubernetes {
          settei = setteiPackage;
        };
      setteiDhallPackage =
        pkgs.haskell.lib.dontCheck (
          haskellPackages.callCabal2nix "settei-dhall" ../settei-dhall {
            dhall = dhallPackage;
            dhall-json = dhallJsonPackage;
            settei = setteiPackage;
          }
        );
      setteiOptparseApplicativePackage =
        # Cabal runs this package's tests with one coherent solver plan. The nixpkgs
        # tasty derivation still embeds optparse-applicative 0.18, so enabling the same
        # tests here would mix two optparse ABIs in one component graph.
        pkgs.haskell.lib.dontCheck (
          haskellPackages.callCabal2nix
            "settei-optparse-applicative"
            ../settei-optparse-applicative
            {
              optparse-applicative = optparseApplicativePackage;
              settei = setteiPackage;
              settei-env = setteiEnvPackage;
            }
        );
      setteiFormatsPackage =
        pkgs.haskell.lib.dontCheck (
          haskellPackages.callCabal2nix "settei-formats" ../settei-formats {
            optparse-applicative = optparseApplicativePackage;
            settei = setteiPackage;
            settei-dhall = setteiDhallPackage;
            settei-kdl = setteiKdlPackage;
            settei-optparse-applicative = setteiOptparseApplicativePackage;
            settei-yaml = setteiYamlPackage;
          }
        );
      setteiExampleCliPackage =
        pkgs.haskell.lib.dontCheck (
          haskellPackages.callCabal2nix "settei-example-cli" ../examples/settei-cli {
            optparse-applicative = optparseApplicativePackage;
            settei = setteiPackage;
            settei-dhall = setteiDhallPackage;
            settei-env = setteiEnvPackage;
            settei-kdl = setteiKdlPackage;
            settei-optparse-applicative = setteiOptparseApplicativePackage;
            settei-yaml = setteiYamlPackage;
          }
        );
      setteiExampleServicePackage =
        pkgs.haskell.lib.dontCheck (
          haskellPackages.callCabal2nix "settei-example-service" ../examples/settei-service {
            optparse-applicative = optparseApplicativePackage;
            settei = setteiPackage;
            settei-dhall = setteiDhallPackage;
            settei-env = setteiEnvPackage;
            settei-kdl = setteiKdlPackage;
            settei-optparse-applicative = setteiOptparseApplicativePackage;
            settei-yaml = setteiYamlPackage;
          }
        );
      setteiExampleConformancePackage =
        # Cabal is the test authority for these examples. nixpkgs' tasty closure still
        # carries optparse-applicative 0.18, while the examples deliberately test the
        # workspace's pinned 0.19 API, so Nix builds their test-free package artifacts.
        pkgs.haskell.lib.dontCheck (
          haskellPackages.callCabal2nix
            "settei-example-conformance"
            ../examples/settei-conformance
            {
              optparse-applicative = optparseApplicativePackage;
              settei = setteiPackage;
              settei-dhall = setteiDhallPackage;
              settei-env = setteiEnvPackage;
              settei-example-cli = setteiExampleCliPackage;
              settei-example-service = setteiExampleServicePackage;
              settei-kdl = setteiKdlPackage;
              settei-yaml = setteiYamlPackage;
            }
        );

      baseDevPackages = [
        pkgs.zlib
        pkgs.just
        pkgs.pkg-config
      ];

      shellHook = ''
        ${config.pre-commit.installationScript}
      '';

      mkProjectShell = ghc: hsdev.mkDevShell {
        inherit ghc;
        extraNativeBuildInputs = baseDevPackages ++ config.haskellProject.extraDevPackages;
        withHls = true;
        inherit shellHook;
      };
    in
    {
      packages.default = setteiPackage;
      packages.settei-example-cli = setteiExampleCliPackage;
      packages.settei-example-conformance = setteiExampleConformancePackage;
      packages.settei-example-service = setteiExampleServicePackage;
      packages.settei-dhall = setteiDhallPackage;
      packages.settei-env = setteiEnvPackage;
      packages.settei-formats = setteiFormatsPackage;
      packages.settei-kdl = setteiKdlPackage;
      packages.settei-kubernetes = setteiKubernetesPackage;
      packages.settei-optparse-applicative = setteiOptparseApplicativePackage;
      packages.settei-yaml = setteiYamlPackage;

      devShells.default = mkProjectShell "ghc9124";
      devShells."ghc9124" = mkProjectShell "ghc9124";
    };
}
