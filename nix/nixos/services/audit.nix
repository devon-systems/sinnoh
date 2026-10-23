_: {
  flake.nixosModules.default = {lib, ...}: {
    users.groups.audit = {};
    systemd.services.alloy.serviceConfig.SupplementaryGroups = ["audit"];
    security.audit = {
      enable = true;
      backlogLimit = 8192;
      rules = [
        # Command-line arguments can contain credentials. Keep executable, UID, and PID history.
        "-a never,exclude -F msgtype=EXECVE"
        "-a never,exclude -F msgtype=PROCTITLE"
        "-a always,exit -F arch=b64 -S execve,execveat -F success=1 -k process_exec"
        "-a always,exit -F arch=b32 -S execve,execveat -F success=1 -k process_exec"
      ];
    };
    security.auditd = {
      enable = true;
      settings = {
        log_group = "audit";
        max_log_file = 64;
        num_logs = 16;
        max_log_file_action = "ROTATE";
        space_left_action = "SYSLOG";
        admin_space_left_action = "SUSPEND";
        disk_full_action = "SUSPEND";
        disk_error_action = "SYSLOG";
      };
    };
    systemd.services.auditd.serviceConfig = {
      Group = "audit";
      LogsDirectoryMode = lib.mkForce "0750";
    };
    environment.etc."alloy/linux-audit.alloy".text = ''
      local.file_match "linux_audit" {
        path_targets = [{
          __path__ = "/var/log/audit/audit.log",
          job = "linux-audit",
          cluster = "sinnoh",
          host = constants.hostname,
          node = constants.hostname,
        }]
      }
      loki.source.file "linux_audit" {
        targets = local.file_match.linux_audit.targets
        forward_to = [loki.process.redact.receiver]
        tail_from_end = false
      }
    '';
  };
}
