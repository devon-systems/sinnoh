_: {
  flake.nixosModules.canalave = {config, ...}: {
    services.k3s = {
      role = "agent";
      serverAddr = "https://10.254.0.2:6443";

      extraFlags = [
        "--node-ip=10.254.0.3"
      ];
    };

    services.restic.backups.k3s-local-path = {
      paths = ["/var/lib/rancher/k3s/storage"];
      repository = "rclone:b2:aly-backups/sinnoh/canalave/k3s-local-path";
      extraBackupArgs = [
        "--cleanup-cache"
        # CloudNativePG volumes are backed up by Barman.
        "--exclude=/var/lib/rancher/k3s/storage/*_cnpg-system_*"
      ];
      initialize = true;
      passwordFile = config.sops.secrets.restic-password.path;
      rcloneConfigFile = config.sops.secrets.rclone-b2.path;
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 12"
      ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "3h";
      };
    };
  };
}
