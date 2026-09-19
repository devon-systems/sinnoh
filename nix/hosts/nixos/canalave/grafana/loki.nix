_: {
  flake.nixosModules.canalave = {config, ...}: {
    services.loki = {
      enable = true;
      configuration = {
        auth_enabled = false;

        server = {
          http_listen_port = 3030;
          grpc_listen_port = 0;
        };

        common = {
          path_prefix = "/var/lib/loki";
          replication_factor = 1;
          ring.kvstore.store = "inmemory";
          storage.filesystem = {
            chunks_directory = "/var/lib/loki/chunks";
            rules_directory = "/var/lib/loki/rules";
          };
        };

        compactor = {
          working_directory = "/var/lib/loki/compactor";
          retention_enabled = true;
          delete_request_store = "filesystem";
        };

        limits_config = {
          retention_period = "30d";
          # Exact top-path queries aggregate more than the default 500 paths.
          max_query_series = 10000;
        };

        schema_config.configs = [
          {
            from = "2024-01-01";
            store = "tsdb";
            object_store = "filesystem";
            schema = "v13";
            index = {
              prefix = "index_";
              period = "24h";
            };
          }
        ];

        analytics.reporting_enabled = false;
      };
    };

    services.restic.backups.loki = {
      paths = ["/var/lib/loki"];
      repository = "rclone:b2:aly-backups/sinnoh/canalave/loki";
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
