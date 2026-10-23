_: {
  flake.nixosModules.canalave = {
    services.prometheus = {
      enable = true;
      port = 3020;
      retentionTime = "30d";
      extraFlags = ["--web.enable-remote-write-receiver"];
      globalConfig = {
        scrape_interval = "30s";
        evaluation_interval = "30s";
      };
      scrapeConfigs = [
        {
          job_name = "loki";
          static_configs = [
            {
              targets = ["127.0.0.1:3030"];
              labels.instance = "canalave";
            }
          ];
        }
        {
          job_name = "node";
          static_configs = [
            {
              targets = ["sunnyshore.sinnoh:3021"];
              labels.instance = "sunnyshore";
            }
            {
              targets = ["canalave.sinnoh:3021"];
              labels.instance = "canalave";
            }
          ];
        }
      ];
    };
  };
}
