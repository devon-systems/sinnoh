_: {
  flake.nixosModules.canalave = {
    config,
    self,
    ...
  }: {
    sops.secrets.observability-alertmanager-smtp-password = {
      sopsFile = self + "/secrets/observability-alertmanager.yaml";
      key = "SMTP_PASSWORD";
      mode = "0400";
      restartUnits = ["alertmanager.service"];
    };

    systemd.services.alertmanager.serviceConfig.LoadCredential = [
      "smtp-password:${config.sops.secrets.observability-alertmanager-smtp-password.path}"
    ];

    services.prometheus = {
      globalConfig.external_labels.cluster = "sinnoh";
      webExternalUrl = "http://canalave.sinnoh:3020";
      alertmanagers = [{static_configs = [{targets = ["127.0.0.1:3040"];}];}];
      alertmanager = {
        enable = true;
        listenAddress = "0.0.0.0";
        port = 3040;
        openFirewall = false;
        webExternalUrl = "http://canalave.sinnoh:3040";
        extraFlags = ["--cluster.listen-address="];
        configuration = {
          global = {
            smtp_smarthost = "smtp.resend.com:587";
            smtp_from = "Cluster alerts <alerts@aly.social>";
            smtp_auth_username = "resend";
            smtp_auth_password_file = "/run/credentials/alertmanager.service/smtp-password";
            smtp_require_tls = true;
          };
          route = {
            receiver = "sinnoh";
            group_by = ["cluster" "namespace" "alertname"];
            group_wait = "30s";
            group_interval = "5m";
            repeat_interval = "12h";
            routes = [
              {
                matchers = [''severity="critical"''];
                repeat_interval = "1h";
              }
            ];
          };
          inhibit_rules = [
            {
              source_matchers = [''alertname="NodeDiskSpaceCritical"''];
              target_matchers = [''alertname="NodeDiskSpaceLow"''];
              equal = ["cluster" "instance" "device" "mountpoint"];
            }
            {
              source_matchers = [''alertname="KubernetesDeploymentUnavailable"''];
              target_matchers = [''alertname="KubernetesDeploymentReplicasMissing"''];
              equal = ["cluster" "namespace" "deployment"];
            }
            {
              source_matchers = [''alertname="NodeDown"''];
              target_matchers = [''alertname="NodeMemoryLow"''];
              equal = ["cluster" "instance"];
            }
            {
              source_matchers = [''alertname="KubernetesDeploymentUnavailable"'' ''namespace=~"slingshot|skytrace"''];
              target_matchers = [''alertname=~"PublicServiceHTTPErrorRateHigh|PublicServiceLatencyHigh"''];
              equal = ["cluster" "namespace"];
            }
          ];
          receivers = [
            {
              name = "sinnoh";
              email_configs = [
                {
                  to = "alyraffauf@fastmail.com";
                  send_resolved = true;
                }
              ];
            }
          ];
        };
      };
    };

    services.restic.backups.alertmanager = {
      paths = ["/var/lib/alertmanager"];
      repository = "rclone:b2:aly-backups/sinnoh/canalave/alertmanager";
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
