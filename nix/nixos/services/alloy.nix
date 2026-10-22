_: {
  flake.nixosModules.alloy = {
    config,
    lib,
    pkgs,
    ...
  }: let
    lokiUrl = "http://canalave.sinnoh:3030/loki/api/v1/push";
  in {
    services.alloy = {
      enable = true;
      extraFlags = ["--storage.path=/var/lib/alloy/data-alloy" "--disable-reporting"];
    };

    systemd.services.observability-canary = {
      description = "Emit a log collection heartbeat";
      serviceConfig.Type = "oneshot";
      script = ''
        echo "observability_canary timestamp=$(${pkgs.coreutils}/bin/date +%s)"
      '';
    };
    systemd.timers.observability-canary = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "1m";
        OnUnitActiveSec = "1m";
      };
    };

    environment.etc."alloy/config.alloy".text =
      ''
        loki.write "default" {
          endpoint {
            url = "${lokiUrl}"
          }
        }

        loki.process "redact" {
          forward_to = [loki.write.default.receiver]
          stage.replace {
            expression = `(?i)(?:x-plex-token|plexonlinetoken|access_token|refresh_token|api[_-]?key|password|client_secret|authorization)["' ]*(?:[:=]|%3[dDaA])["' ]*(?:bearer\s+|basic\s+)?([^&\s"'<>]+)`
            replace = "[REDACTED]"
          }
        }

        loki.relabel "journal" {
          forward_to = []

          rule {
            source_labels = ["__journal__systemd_unit"]
            target_label  = "unit"
          }

          rule {
            source_labels = ["__journal__systemd_unit"]
            regex         = "comin[.]service"
            target_label  = "service"
            replacement   = "comin"
          }

          rule {
            source_labels = ["__journal__systemd_user_unit"]
            target_label  = "user_unit"
          }
        }

        loki.source.journal "read" {
          forward_to    = [loki.process.redact.receiver]
          relabel_rules = loki.relabel.journal.rules
          max_age       = "168h"
          labels        = {
            job  = "systemd-journal",
            host = "${config.networking.hostName}",
            node = "${config.networking.hostName}",
            cluster = "sinnoh",
          }
        }

        prometheus.exporter.self "host" {}

        discovery.relabel "alloy_self" {
          targets = prometheus.exporter.self.host.targets
          rule {
            target_label = "instance"
            replacement = "${config.networking.hostName}"
          }
          rule {
            target_label = "cluster"
            replacement = "sinnoh"
          }
        }

        prometheus.scrape "alloy_self" {
          targets = discovery.relabel.alloy_self.output
          job_name = "alloy-host"
          forward_to = [prometheus.remote_write.comin.receiver]
        }

        prometheus.remote_write "comin" {
          endpoint {
            url = "http://canalave.sinnoh:3020/api/v1/write"
          }
        }
      ''
      + lib.optionalString config.services.comin.enable ''
        prometheus.scrape "comin" {
          targets = [{
            __address__ = "127.0.0.1:${toString config.services.comin.exporter.port}",
            instance    = "${config.networking.hostName}",
            host        = "${config.networking.hostName}",
            cluster     = "sinnoh",
          }]
          job_name        = "comin"
          scrape_interval = "30s"
          forward_to      = [prometheus.remote_write.comin.receiver]
        }
      '';
  };
}
