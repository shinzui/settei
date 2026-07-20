{ ... }:
{
  perSystem = { pkgs, ... }: {
    haskellProject.extraDevPackages = [
      pkgs.kubectl
      pkgs.kubeconform
    ];
  };
}
