_: {
  flake.nixosModules.canalave = {
    config,
    self,
    ...
  }: {
    sops.secrets = {
      observability-grafana-admin-password = {
        sopsFile = self + "/secrets/observability-grafana.yaml";
        key = "ADMIN_PASSWORD";
        owner = "grafana";
        mode = "0400";
      };

      observability-grafana-secret-key = {
        sopsFile = self + "/secrets/observability-grafana.yaml";
        key = "SECRET_KEY";
        owner = "grafana";
        mode = "0400";
      };
    };

    services.grafana = {
      enable = true;
      settings = {
        security = {
          admin_password = "$__file{${config.sops.secrets.observability-grafana-admin-password.path}}";
          secret_key = "$__file{${config.sops.secrets.observability-grafana-secret-key.path}}";
        };

        server = {
          http_addr = "0.0.0.0";
          http_port = 3010;
          domain = "grafana.canalave.sinnoh";
        };
      };

      provision = {
        enable = true;
        datasources.settings = {
          prune = true;
          deleteDatasources = [
            {
              name = "Prometheus";
              orgId = 1;
            }
            {
              name = "Loki";
              orgId = 1;
            }
          ];

          datasources = [
            {
              name = "Sinnoh Prometheus";
              uid = "P9A18226D8188C8FB";
              type = "prometheus";
              access = "proxy";
              url = "http://127.0.0.1:3020";
              jsonData.timeInterval = "30s";
            }
            {
              name = "Sinnoh Loki";
              uid = "P246360FA49B4ADE8";
              type = "loki";
              access = "proxy";
              url = "http://127.0.0.1:3030";
            }
            {
              name = "Johto Prometheus";
              uid = "P9F1EC05FDA06B452";
              jsonData.timeInterval = "30s";
              type = "prometheus";
              access = "proxy";
              url = "http://100.81.61.31:3020";
            }
            {
              name = "Johto Loki";
              uid = "P9B94E49EB647514A";
              type = "loki";
              access = "proxy";
              url = "http://100.81.61.31:3030";
            }
          ];
        };
      };
    };

    services.restic.backups.grafana = {
      paths = ["/var/lib/grafana"];
      repository = "rclone:b2:aly-backups/sinnoh/canalave/grafana";
      extraBackupArgs = ["--cleanup-cache"];
      initialize = true;
      passwordFile = config.sops.secrets.restic-password.path;
      pruneOpts = ["--keep-daily 7" "--keep-weekly 4" "--keep-monthly 12"];
      rcloneConfigFile = config.sops.secrets.rclone-b2.path;
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "3h";
      };
    };
  };
}
