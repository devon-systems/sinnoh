_: {
  flake.nixosModules.canalave = {
    lib,
    pkgs,
    ...
  }: let
    prometheus = {
      type = "prometheus";
      uid = "hoenn-prometheus";
    };
    loki = {
      type = "loki";
      uid = "hoenn-loki";
    };
    node = ''job="node",host=~"$host"'';
    smartctl = ''job="smartctl",host=~"$host",device=~"$drive"'';
    backup = ''job="node",host=~"$host",backup=~"$backup"'';
    btrfs = ''job="node",host=~"$host",filesystem=~"$filesystem"'';
    btrfsAvailable = ''and on (host) (hoenn_btrfs_collector_success{${node}} == 1 and (time() - hoenn_btrfs_collector_last_run_timestamp_seconds{${node}} < 900))'';
    panel = index: specification: {
      id = index + 1;
      inherit (specification) title;
      type = specification.type or "timeseries";
      datasource = specification.datasource or prometheus;
      description = specification.description or "Gaps mean telemetry is unavailable. Sleeping desktops do not report metrics.";
      gridPos = {
        x = lib.mod index 2 * 12;
        y = builtins.div index 2 * 8;
        w = 12;
        h = 8;
      };
      targets = [
        {
          refId = "A";
          inherit (specification) expr;
          legendFormat = specification.legend or "{{host}}";
          range = true;
        }
      ];
      fieldConfig.defaults = {
        unit = specification.unit or "short";
        noValue = "Unknown";
        mappings = specification.mappings or [];
        custom.spanNulls = false;
      };
      options =
        if (specification.type or "") == "logs"
        then {
          showTime = true;
          showLabels = true;
          sortOrder = "Descending";
        }
        else {
          legend = {
            displayMode = "list";
            placement = "bottom";
          };
          tooltip.mode = "multi";
        };
    };
    dashboard = {
      uid = "hoenn-desktops";
      title = "Hoenn desktops";
      description = "Desktop metrics and logs on Mauville. Sleeping or disconnected hosts leave gaps. Linux and macOS expose different collectors.";
      tags = ["hoenn"];
      schemaVersion = 39;
      version = 1;
      editable = false;
      timezone = "browser";
      refresh = "1m";
      time = {
        from = "now-6h";
        to = "now";
      };
      templating.list = [
        {
          name = "host";
          label = "Host";
          type = "query";
          datasource = prometheus;
          query = ''label_values(up{job="node"}, host)'';
          refresh = 2;
          sort = 1;
          multi = true;
          includeAll = true;
          allValue = ".*";
          current = {
            text = "All";
            value = "$__all";
          };
        }
      ];
      panels = lib.imap0 panel [
        {
          title = "Time since last sample";
          description = "Age of the latest node scrape timestamp in the past 24 hours, including sleeping hosts. Unknown means no sample in that window.";
          expr = ''time() - max by (host) (max_over_time(timestamp(up{${node}})[24h:1m]))'';
          unit = "s";
        }
        {
          title = "CPU usage";
          expr = ''1 - avg by (host) (rate(node_cpu_seconds_total{${node},mode="idle"}[$__rate_interval]))'';
          unit = "percentunit";
        }
        {
          title = "Linux memory usage";
          expr = ''1 - node_memory_MemAvailable_bytes{${node}} / node_memory_MemTotal_bytes{${node}}'';
          unit = "percentunit";
        }
        {
          title = "macOS memory usage";
          expr = ''(node_memory_active_bytes{${node}} + node_memory_wired_bytes{${node}} + node_memory_compressed_bytes{${node}}) / node_memory_total_bytes{${node}}'';
          unit = "percentunit";
        }
        {
          title = "Filesystem space used";
          expr = ''1 - node_filesystem_avail_bytes{${node},fstype!~"tmpfs|ramfs"} / node_filesystem_size_bytes{${node},fstype!~"tmpfs|ramfs"}'';
          legend = "{{host}} {{mountpoint}}";
          unit = "percentunit";
        }
        {
          title = "Network receive rate";
          expr = ''rate(node_network_receive_bytes_total{${node},device!~"lo|lo0|veth.*|cali.*"}[$__rate_interval])'';
          legend = "{{host}} {{device}}";
          unit = "Bps";
        }
        {
          title = "Network transmit rate";
          expr = ''rate(node_network_transmit_bytes_total{${node},device!~"lo|lo0|veth.*|cali.*"}[$__rate_interval])'';
          legend = "{{host}} {{device}}";
          unit = "Bps";
        }
        {
          title = "Disk I/O rate";
          expr = ''rate(node_disk_read_bytes_total{${node}}[$__rate_interval]) + rate(node_disk_written_bytes_total{${node}}[$__rate_interval])'';
          legend = "{{host}} {{device}}";
          unit = "Bps";
        }
        {
          title = "Hardware temperature";
          expr = ''node_hwmon_temp_celsius{${node}}'';
          legend = "{{host}} {{chip}} {{sensor}}";
          unit = "celsius";
        }
        {
          title = "Battery charge";
          expr = ''node_power_supply_capacity{${node}}'';
          legend = "{{host}} {{power_supply}}";
          unit = "percent";
        }
        {
          title = "Failed system services";
          expr = ''sum by (host) (node_systemd_unit_state{${node},state="failed"})'';
        }
        {
          title = "Desktop logs";
          type = "logs";
          datasource = loki;
          description = "Linux system and user journals, plus macOS file-based system logs. Filter Linux logs by unit, user_unit, or level in Explore.";
          expr = ''{host=~"$host",job=~"systemd-journal|system-log"}'';
        }
      ];
    };
    driveHealth =
      dashboard
      // {
        uid = "hoenn-drive-health";
        title = "Hoenn drive health";
        description = "Linux SMART and NVMe health collected every five minutes. Unsupported or sleeping drives may omit metrics; exporter availability alone does not prove drive health.";
        templating.list =
          dashboard.templating.list
          ++ [
            {
              name = "drive";
              label = "Drive";
              type = "query";
              datasource = prometheus;
              query = ''label_values(smartctl_device{job="smartctl",host=~"$host"}, device)'';
              refresh = 2;
              sort = 1;
              multi = true;
              includeAll = true;
              allValue = ".*";
              current = {
                text = "All";
                value = "$__all";
              };
            }
          ];
        panels = lib.imap0 panel [
          {
            title = "SMART exporter reachable";
            expr = ''up{job="smartctl",host=~"$host"}'';
            description = "Whether Alloy could scrape the local exporter. Check discovered drives and command exit status for collection failures.";
            unit = "bool";
          }
          {
            title = "Drives discovered";
            expr = ''smartctl_devices{job="smartctl",host=~"$host"}'';
            description = "Number of automatically discovered drives. A drive that cannot be discovered will not have per-drive metrics.";
          }
          {
            title = "SMART health";
            expr = ''smartctl_device_smart_status{${smartctl}}'';
            legend = "{{host}} {{device}}";
            description = "Drive-reported overall SMART status. A passing result does not rule out failures indicated by individual counters.";
            mappings = [
              {
                type = "value";
                options = {
                  "0" = {
                    text = "Failing";
                    color = "red";
                  };
                  "1" = {
                    text = "Passing";
                    color = "green";
                  };
                };
              }
            ];
          }
          {
            title = "Drive temperature";
            expr = ''smartctl_device_temperature{${smartctl}}'';
            legend = "{{host}} {{device}} {{temperature_type}}";
            unit = "celsius";
          }
          {
            title = "NVMe endurance used";
            expr = ''smartctl_device_percentage_used{${smartctl}}'';
            legend = "{{host}} {{device}}";
            description = "Manufacturer estimate of endurance consumed, which can exceed 100%. SATA SSD wear attributes vary by manufacturer.";
            unit = "percent";
          }
          {
            title = "NVMe available spare";
            expr = ''smartctl_device_available_spare{${smartctl}}'';
            legend = "{{host}} {{device}}";
            unit = "percent";
          }
          {
            title = "NVMe critical warning flags";
            expr = ''smartctl_device_critical_warning{${smartctl}}'';
            legend = "{{host}} {{device}}";
            description = "Controller warning bitmask. Zero means no critical warning flags are set.";
          }
          {
            title = "NVMe media and data integrity errors";
            expr = ''smartctl_device_media_errors{${smartctl}}'';
            legend = "{{host}} {{device}}";
            description = "Lifetime count of unrecovered data integrity errors reported by the controller.";
          }
          {
            title = "ATA reallocated, pending, and uncorrectable sectors";
            expr = ''smartctl_device_attribute{${smartctl},attribute_id=~"5|197|198",attribute_value_type="raw"}'';
            legend = "{{host}} {{device}} {{attribute_name}}";
            description = "Raw ATA SMART attributes 5, 197, and 198 where the drive provides them. Interpret according to the drive manufacturer.";
          }
          {
            title = "ATA SSD wear indicators";
            expr = ''smartctl_device_attribute{${smartctl},attribute_name=~".*(Wear|Life).*",attribute_value_type="value"}'';
            legend = "{{host}} {{device}} {{attribute_name}}";
            description = "Normalized vendor-specific wear and lifetime attributes. These values are not a universal percentage; interpret them using the drive manufacturer's definitions.";
          }
          {
            title = "Drive power-on time";
            expr = ''smartctl_device_power_on_seconds{${smartctl}}'';
            legend = "{{host}} {{device}}";
            unit = "s";
          }
          {
            title = "SMART command exit status";
            expr = ''smartctl_device_smartctl_exit_status{${smartctl}}'';
            legend = "{{host}} {{device}}";
            description = "smartctl exit-status bitmask. Nonzero can indicate a query failure or drive-reported health and error conditions.";
          }
        ];
      };
    dataProtection =
      dashboard
      // {
        uid = "hoenn-data-protection";
        title = "Hoenn data protection";
        description = "Restic completion results and Btrfs scrub/device errors. Backup history starts when reporting is enabled; scrub history comes from existing records. Unknown means no result is available.";
        time = {
          from = "now-7d";
          to = "now";
        };
        templating.list =
          dashboard.templating.list
          ++ map (item: {
            inherit (item) name query label;
            type = "query";
            datasource = prometheus;
            refresh = 2;
            sort = 1;
            multi = true;
            includeAll = true;
            allValue = ".*";
            current = {
              text = "All";
              value = "$__all";
            };
          }) [
            {
              name = "backup";
              label = "Backup";
              query = ''label_values(hoenn_backup_job_info{host=~"$host"}, backup)'';
            }
            {
              name = "filesystem";
              label = "Filesystem";
              query = ''label_values(hoenn_btrfs_device_info{host=~"$host"}, filesystem)'';
            }
          ];
        panels = lib.imap0 panel [
          {
            title = "Configured backup jobs";
            expr = ''sum by (host) (hoenn_backup_job_info{${backup}})'';
            description = "Scheduled system and user Restic jobs registered for reporting.";
          }
          {
            title = "Last completed backup succeeded";
            expr = ''hoenn_backup_last_run_success{${backup}}'';
            legend = "{{host}} {{scope}}/{{owner}} {{backup}}";
            unit = "bool";
            description = "Result of the complete systemd backup job, including preparation, pruning, checks, and cleanup. Unknown until the first reported completion.";
          }
          {
            title = "Time since successful backup";
            expr = ''time() - hoenn_backup_last_success_timestamp_seconds{${backup}}'';
            legend = "{{host}} {{scope}}/{{owner}} {{backup}}";
            unit = "s";
            description = "A failed job preserves the previous successful completion time. Unknown means no successful completion has been observed.";
          }
          {
            title = "Time since backup completion";
            expr = ''time() - hoenn_backup_last_completion_timestamp_seconds{${backup}}'';
            legend = "{{host}} {{scope}}/{{owner}} {{backup}}";
            unit = "s";
          }
          {
            title = "Btrfs collection succeeded";
            expr = ''hoenn_btrfs_collector_success{${node}}'';
            unit = "bool";
            description = "Whether the last collection could read mounted-device statistics and available scrub records. This is collector health, not filesystem health.";
          }
          {
            title = "Time since Btrfs collection";
            expr = ''time() - hoenn_btrfs_collector_last_run_timestamp_seconds{${node}}'';
            unit = "s";
            description = "Collection runs every five minutes. Btrfs result panels omit samples if collection failed or is more than 15 minutes old.";
          }
          {
            title = "Last completed scrub succeeded";
            expr = ''hoenn_btrfs_scrub_last_run_success{${btrfs}} ${btrfsAvailable}'';
            legend = "{{host}} {{filesystem}} device {{device}}";
            unit = "bool";
            description = "Success requires a completed, uncanceled scrub with no uncorrectable or allocation errors. Corrected errors are shown separately.";
          }
          {
            title = "Time since successful scrub";
            expr = ''(time() - hoenn_btrfs_scrub_last_success_timestamp_seconds{${btrfs}}) ${btrfsAvailable}'';
            legend = "{{host}} {{filesystem}} device {{device}}";
            unit = "s";
          }
          {
            title = "Time since scrub completion";
            expr = ''(time() - hoenn_btrfs_scrub_last_completion_timestamp_seconds{${btrfs}}) ${btrfsAvailable}'';
            legend = "{{host}} {{filesystem}} device {{device}}";
            unit = "s";
          }
          {
            title = "Last scrub duration";
            expr = ''hoenn_btrfs_scrub_duration_seconds{${btrfs}} ${btrfsAvailable}'';
            legend = "{{host}} {{filesystem}} device {{device}}";
            unit = "s";
          }
          {
            title = "Btrfs device error counters";
            expr = ''hoenn_btrfs_device_errors_total{${btrfs}} ${btrfsAvailable}'';
            legend = "{{host}} {{filesystem}} device {{device}} {{operation}}";
            description = "Persistent read, write, flush, corruption, and generation error counters. Collection never resets them.";
          }
          {
            title = "Errors in the last completed scrub";
            expr = ''hoenn_btrfs_scrub_errors{${btrfs}} ${btrfsAvailable}'';
            legend = "{{host}} {{filesystem}} device {{device}} {{kind}}";
          }
          {
            title = "Latest scrub record completed";
            expr = ''hoenn_btrfs_scrub_finished{${btrfs}} ${btrfsAvailable}'';
            legend = "{{host}} {{filesystem}} device {{device}}";
            unit = "bool";
            description = "False for running, interrupted, or canceled records. Prior completed results remain visible while a new scrub is incomplete.";
          }
          {
            title = "Textfile collection errors";
            expr = ''node_textfile_scrape_error{${node}}'';
            description = "Nonzero means Alloy could not read or parse a metrics file.";
          }
        ];
      };
  in {
    services.grafana.provision.dashboards.settings.providers = [
      {
        name = "hoenn-desktops";
        folder = "Hoenn";
        options.path = pkgs.linkFarm "hoenn-dashboards" (map (item: {
          name = "${item.uid}.json";
          path = pkgs.writeText "${item.uid}.json" (builtins.toJSON item);
        }) [dashboard driveHealth dataProtection]);
      }
    ];
  };
}
