_: {
  perSystem = {
    inputs',
    pkgs,
    ...
  }: {
    devShells.default = pkgs.mkShell {
      packages = [
        inputs'.blzrd.packages.blzrd
        pkgs.age
        pkgs.bun
        pkgs.fluxcd
        pkgs.git
        pkgs.just
        pkgs.kubectl
        pkgs.kubernetes-helm
        pkgs.kustomize
        pkgs.nh
        pkgs.nixd
        pkgs.opentofu
        pkgs.sops
        pkgs.ssh-to-age
      ];

      shellHook = ''
        export FLAKE="." NH_FLAKE="."
        echo "👋 Welcome to the sinnoh devShell!"
      '';
    };
  };
}
