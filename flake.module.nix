{ ... }:
{
  perSystem = { pkgs, ... }: {
    haskellProject.extraDevPackages = [
      pkgs.kubectl
      pkgs.kubeconform
    ];

    # Enforce the shared docs/adr/profile.dhall architecture-decision profile
    # (strict fields, unique ADR-N handles, log.md freshness) on every commit
    # that touches the ADR bundle. `okf` itself is not packaged in nixpkgs, so
    # this hook relies on it being on PATH (as it already is in this
    # workstation's environment) rather than adding a new flake input.
    pre-commit.settings.hooks.okf-adr-validate = {
      enable = true;
      name = "okf-adr-validate";
      description = "Validate docs/adr against the shared architecture-decision profile.";
      entry = "okf validate docs/adr --profile docs/adr/profile.dhall --profile-enforce --log-enforce";
      language = "system";
      pass_filenames = false;
      files = "^docs/adr/";
    };
  };
}
