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
      scrapeConfigs = map (scrape:
        scrape
        // {
          relabel_configs =
            (scrape.relabel_configs or [])
            ++ [
              {
                target_label = "cluster";
                replacement = "sinnoh";
              }
            ];
        }) [
        {
          job_name = "prometheus";
          static_configs = [
            {
              targets = ["127.0.0.1:3020"];
              labels = {
                instance = "canalave";
                host = "canalave";
                os = "linux";
              };
            }
          ];
        }
        {
          job_name = "alertmanager";
          static_configs = [
            {
              targets = ["127.0.0.1:3040"];
              labels = {
                instance = "canalave";
                host = "canalave";
                os = "linux";
              };
            }
          ];
        }
        {
          job_name = "loki";
          static_configs = [
            {
              targets = ["127.0.0.1:3030"];
              labels = {
                instance = "canalave";
                host = "canalave";
                os = "linux";
              };
            }
          ];
        }
        {
          job_name = "node";
          static_configs = [
            {
              targets = ["sunnyshore.sinnoh:3021"];
              labels = {
                instance = "sunnyshore";
                host = "sunnyshore";
                os = "linux";
              };
            }
            {
              targets = ["canalave.sinnoh:3021"];
              labels = {
                instance = "canalave";
                host = "canalave";
                os = "linux";
              };
            }
          ];
        }
      ];
    };
  };
}
