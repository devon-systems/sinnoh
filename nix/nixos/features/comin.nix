{inputs, ...}: {
  flake.nixosModules.comin = {...}: {
    imports = [inputs.comin.nixosModules.comin];

    services.comin = {
      enable = true;
      exporter = {
        listen_address = "127.0.0.1";
        port = 4243;
      };

      remotes = [
        {
          name = "origin";
          url = "https://github.com/devon-systems/sinnoh.git";
          branches.main.name = "master";
          poller.period = 600;
        }
      ];
    };
  };
}
