_: {
  perSystem = {
    treefmt.config = {
      programs = {
        alejandra.enable = true;
        deadnix.enable = true;
        prettier.enable = true;
        shellcheck.enable = true;
        shfmt = {
          enable = true;
          indent_size = 2;
        };
        statix.enable = true;
        terraform.enable = true;
      };

      settings.excludes = [
        "secrets/**"
        "k8s/flux-system/gotk-components.yaml"
        "**/facter.json"
      ];
    };
  };
}
