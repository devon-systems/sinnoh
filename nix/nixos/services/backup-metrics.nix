_: {
  flake.nixosModules.backups = {
    config,
    lib,
    pkgs,
    ...
  }: let
    jobs = builtins.attrNames config.services.restic.backups;
    directory = "/var/lib/sinnoh-backup-metrics";
    reporter = pkgs.writeShellApplication {
      name = "sinnoh-backup-metrics";
      runtimeInputs = [pkgs.python3 pkgs.systemd pkgs.coreutils];
      text = ''exec python3 ${../../../scripts/backup-metrics.py} "$@"'';
    };
  in {
    services.prometheus.exporters.node = {
      enabledCollectors = ["textfile"];
      extraFlags = ["--collector.textfile.directory=${directory}"];
    };
    systemd.tmpfiles.rules = ["d ${directory} 0755 root root -"];
    systemd.services =
      lib.listToAttrs (map (job: {
          name = "restic-backups-${job}";
          value.serviceConfig.ExecStopPost = lib.mkAfter ["-${lib.getExe reporter} ${lib.escapeShellArg job}"];
        })
        jobs)
      // {
        sinnoh-backup-metrics-seed = {
          description = "Seed backup reporting from completed systemd results";
          wantedBy = ["multi-user.target"];
          after = ["systemd-tmpfiles-setup.service"];
          before = map (job: "restic-backups-${job}.service") jobs;
          serviceConfig.Type = "oneshot";
          script = lib.concatMapStringsSep "\n" (job: "${lib.getExe reporter} --seed ${lib.escapeShellArg job}") jobs;
        };
      };
  };
}
