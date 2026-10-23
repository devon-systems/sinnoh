_: {
  flake.nixosModules.canalave = {
    config,
    lib,
    pkgs,
    ...
  }: let
    helpers = import ./_lib.nix {
      inherit lib;
      datasources = config.services.grafana.provision.datasources.settings.datasources;
      interval = "1m";
    };
    inherit (helpers) target;
    prometheus = helpers.source "Hoenn Prometheus";
    loki = helpers.source "Hoenn Loki";
    node = ''job="node",instance=~"$host"'';
    smartctl = ''job="smartctl",instance=~"$host",device=~"$drive"'';
    backup = ''job="node",instance=~"$host",backup=~"$backup"'';
    btrfs = ''job="node",instance=~"$host",filesystem=~"$filesystem"'';
    btrfsAvailable = ''and on (host) (btrfs_collector_success{${node}} == 1 and (time() - btrfs_collector_last_run_timestamp_seconds{${node}} < 900))'';
    panel = helpers.panel prometheus;
    variable = helpers.variable prometheus;
    dashboard = helpers.dashboard prometheus {
      uid = "hoenn-desktops";
      title = "Hoenn desktops";
      description = "Desktop metrics and logs on Mauville. Sleeping or disconnected hosts leave gaps. Linux and macOS expose different collectors.";
      tags = ["hoenn"];
      variables = [
        (variable "host" ''label_values(up{job="node"}, instance)'')
      ];
      panels = [
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
            (variable "drive" ''label_values(smartctl_device{job="smartctl",host=~"$host"}, device)'')
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
          ++ map (item: (variable item.name item.query) // {inherit (item) label;}) [
            {
              name = "backup";
              label = "Backup";
              query = ''label_values(restic_backup_job_info{instance=~"$host"}, backup)'';
            }
            {
              name = "filesystem";
              label = "Filesystem";
              query = ''label_values(btrfs_device_info{host=~"$host"}, filesystem)'';
            }
          ];
        panels = lib.imap0 panel [
          {
            title = "Configured backup jobs";
            expr = ''sum by (host) (restic_backup_job_info{${backup}})'';
            description = "Scheduled system and user Restic jobs registered for reporting.";
          }
          {
            title = "Last completed backup succeeded";
            expr = ''restic_backup_last_run_success{${backup}}'';
            legend = "{{host}} {{scope}}/{{owner}} {{backup}}";
            unit = "bool";
            description = "Result of the complete systemd backup job, including preparation, pruning, checks, and cleanup. Unknown until the first reported completion.";
          }
          {
            title = "Time since successful backup";
            expr = ''time() - restic_backup_last_success_timestamp_seconds{${backup}}'';
            legend = "{{host}} {{scope}}/{{owner}} {{backup}}";
            unit = "s";
            description = "A failed job preserves the previous successful completion time. Unknown means no successful completion has been observed.";
          }
          {
            title = "Time since backup completion";
            expr = ''time() - restic_backup_last_completion_timestamp_seconds{${backup}}'';
            legend = "{{host}} {{scope}}/{{owner}} {{backup}}";
            unit = "s";
          }
          {
            title = "Btrfs collection succeeded";
            expr = ''btrfs_collector_success{${node}}'';
            unit = "bool";
            description = "Whether the last collection could read mounted-device statistics and available scrub records. This is collector health, not filesystem health.";
          }
          {
            title = "Time since Btrfs collection";
            expr = ''time() - btrfs_collector_last_run_timestamp_seconds{${node}}'';
            unit = "s";
            description = "Collection runs every five minutes. Btrfs result panels omit samples if collection failed or is more than 15 minutes old.";
          }
          {
            title = "Last completed scrub succeeded";
            expr = ''btrfs_scrub_last_run_success{${btrfs}} ${btrfsAvailable}'';
            legend = "{{host}} {{filesystem}} device {{device}}";
            unit = "bool";
            description = "Success requires a completed, uncanceled scrub with no uncorrectable or allocation errors. Corrected errors are shown separately.";
          }
          {
            title = "Time since successful scrub";
            expr = ''(time() - btrfs_scrub_last_success_timestamp_seconds{${btrfs}}) ${btrfsAvailable}'';
            legend = "{{host}} {{filesystem}} device {{device}}";
            unit = "s";
          }
          {
            title = "Time since scrub completion";
            expr = ''(time() - btrfs_scrub_last_completion_timestamp_seconds{${btrfs}}) ${btrfsAvailable}'';
            legend = "{{host}} {{filesystem}} device {{device}}";
            unit = "s";
          }
          {
            title = "Last scrub duration";
            expr = ''btrfs_scrub_duration_seconds{${btrfs}} ${btrfsAvailable}'';
            legend = "{{host}} {{filesystem}} device {{device}}";
            unit = "s";
          }
          {
            title = "Btrfs device error counters";
            expr = ''btrfs_device_errors_total{${btrfs}} ${btrfsAvailable}'';
            legend = "{{host}} {{filesystem}} device {{device}} {{operation}}";
            description = "Persistent read, write, flush, corruption, and generation error counters. Collection never resets them.";
          }
          {
            title = "Errors in the last completed scrub";
            expr = ''btrfs_scrub_errors{${btrfs}} ${btrfsAvailable}'';
            legend = "{{host}} {{filesystem}} device {{device}} {{kind}}";
          }
          {
            title = "Latest scrub record completed";
            expr = ''btrfs_scrub_finished{${btrfs}} ${btrfsAvailable}'';
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
    kubernetes =
      dashboard
      // {
        uid = "hoenn-kubernetes-workloads";
        title = "Kubernetes workloads";
        refresh = "30s";
        templating.list = [
          (variable "node" ''label_values(kube_node_info{job="kube-state-metrics"}, node)'')
          (variable "namespace" ''label_values(pod_workload_info{node=~"$node"}, namespace)'')
          (variable "pod" ''label_values(pod_workload_info{node=~"$node",namespace=~"$namespace"}, pod)'')
        ];
        panels = lib.imap0 panel ([
            {
              title = "Collector scrape health";
              expr = ''up{job=~"cadvisor|kube-state-metrics|flux"}'';
              legend = "{{job}} {{instance}}";
              unit = "bool";
            }
            {
              title = "Pod placement";
              type = "table";
              expr = ''pod_workload_info{node=~"$node",namespace=~"$namespace",pod=~"$pod"}'';
              transformations = [
                {
                  id = "filterFieldsByName";
                  options.include.names = ["namespace" "workload" "pod" "node"];
                }
              ];
            }
            {
              title = "Container CPU consumption";
              expr = ''sum by (namespace, pod, container) (rate(container_cpu_usage_seconds_total{job="cadvisor",container!="",container!="POD",namespace=~"$namespace",pod=~"$pod",node=~"$node"}[$__rate_interval]))'';
              legend = "{{namespace}} {{pod}} {{container}}";
              unit = "cores";
            }
            {
              title = "Container memory working set";
              expr = ''container_memory_working_set_bytes{job="cadvisor",container!="",container!="POD",namespace=~"$namespace",pod=~"$pod",node=~"$node"}'';
              legend = "{{namespace}} {{pod}} {{container}}";
              unit = "bytes";
            }
            {
              title = "Container restarts in selected range";
              expr = ''increase(kube_pod_container_status_restarts_total{job="kube-state-metrics",namespace=~"$namespace",pod=~"$pod"}[$__range])'';
              legend = "{{namespace}} {{pod}} {{container}}";
            }
            {
              title = "Active container readiness";
              expr = ''kube_pod_container_status_ready{job="kube-state-metrics",namespace=~"$namespace",pod=~"$pod"} and on (namespace,pod) (kube_pod_status_phase{job="kube-state-metrics",phase=~"Running|Pending|Unknown"} == 1)'';
              legend = "{{namespace}} {{pod}} {{container}}";
              unit = "bool";
            }
            {
              title = "Deployment replicas";
              targets = [(target ''kube_deployment_spec_replicas{job="kube-state-metrics",namespace=~"$namespace"}'' "{{namespace}} {{deployment}} desired") (target ''kube_deployment_status_replicas_available{job="kube-state-metrics",namespace=~"$namespace"}'' "{{namespace}} {{deployment}} available")];
            }
            {
              title = "Pod logs";
              type = "logs";
              datasource = loki;
              expr = ''{cluster="hoenn",job!="kubernetes-events",namespace=~"$namespace",pod=~"$pod",node=~"$node"}'';
            }
            {
              title = "Kubernetes warning events";
              type = "logs";
              datasource = loki;
              expr = ''{cluster="hoenn",job="kubernetes-events",namespace=~"$namespace"} | json | type="Warning"'';
            }
          ]
          ++ (import ./_flux-panels.nix {inherit target;}));
      };
    reporting =
      dashboard
      // {
        uid = "hoenn-reporting-health";
        title = "Reporting health";
        panels = lib.imap0 panel [
          {
            title = "Monitoring scrape health";
            expr = ''up{job=~"prometheus|loki|alloy-host|alloy-kubernetes",instance=~"$host|alloy"}'';
            legend = "{{job}} {{instance}}";
            unit = "bool";
          }
          {
            title = "Queued metric samples";
            expr = ''prometheus_remote_storage_samples_pending{job=~"alloy-host|alloy-kubernetes",instance=~"$host|alloy"}'';
            legend = "{{job}} {{instance}}";
          }
          {
            title = "Failed metric deliveries";
            expr = ''sum by (job,instance) (rate(prometheus_remote_storage_samples_failed_total{job=~"alloy-host|alloy-kubernetes",instance=~"$host|alloy"}[$__rate_interval]))'';
            legend = "{{job}} {{instance}}";
            unit = "ops";
          }
          {
            title = "Dropped log entries";
            expr = ''sum by (job,instance) (rate(loki_write_dropped_entries_total{job=~"alloy-host|alloy-kubernetes",instance=~"$host|alloy"}[$__rate_interval]))'';
            legend = "{{job}} {{instance}}";
            unit = "ops";
          }
          {
            title = "Host log heartbeats in the last five minutes";
            datasource = loki;
            expr = ''sum by (host) (count_over_time({cluster="hoenn",service="observability-canary",host=~"$host"} |= "observability_canary" [5m]))'';
            description = "Each awake host emits one heartbeat per minute. Missing heartbeats can mean the host is asleep or log delivery has stopped.";
          }
          {
            title = "Log coverage by source";
            datasource = loki;
            expr = ''sum by (job) (rate({cluster="hoenn"}[$__rate_interval]))'';
            legend = "{{job}}";
            unit = "ops";
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
        }) [dashboard driveHealth dataProtection kubernetes reporting]);
      }
    ];
  };
}
