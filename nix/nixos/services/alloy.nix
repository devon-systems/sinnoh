_: {
  flake.nixosModules.alloy = {
    config,
    lib,
    ...
  }: let
    lokiUrl = "http://canalave.sinnoh:3030/loki/api/v1/push";
  in {
    services.alloy.enable = true;

    environment.etc."alloy/config.alloy".text =
      ''
        loki.write "default" {
          endpoint {
            url = "${lokiUrl}"
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
          forward_to    = [loki.write.default.receiver]
          relabel_rules = loki.relabel.journal.rules
          max_age       = "12h"
          labels        = {
            job  = "systemd-journal",
            host = "${config.networking.hostName}",
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

        prometheus.remote_write "comin" {
          endpoint {
            url = "http://canalave.sinnoh:3020/api/v1/write"
          }
        }
      '';
  };
}
