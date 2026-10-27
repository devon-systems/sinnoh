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
    };
    inherit (helpers) target;
    prometheus = helpers.source "Kanto Prometheus";
    loki = helpers.source "Kanto Loki";
    variable = helpers.variable prometheus;
    node = ''job="node",instance=~"$host"'';
    backup = ''job="node",instance=~"$host",backup=~"$backup"'';
    lemonade = ''job="lemonade",instance=~"$host"'';
    openWebui = ''job="open-webui"'';
    hostVariable = variable "host" ''label_values(up{job="node"}, instance)'';
    chipName = ''* on (instance, chip) group_left(chip_name) node_hwmon_chip_names{${node}}'';
    inferenceUnits = ''name=~"lemond.service|ollama.service|comfyui.service"'';
    dashboard = specification:
      helpers.dashboard prometheus ({
          description = "Kanto telemetry from Vermilion, collected every 30 seconds. Unknown means telemetry is absent, not healthy.";
          tags = ["kanto"];
          links = [
            {
              type = "dashboards";
              tags = ["kanto"];
              asDropdown = false;
              includeVars = true;
              keepTime = true;
              title = "Kanto";
            }
          ];
          variables = [hostVariable];
        }
        // specification);
    host = dashboard {
      uid = "kanto-host";
      title = "Kanto host";
      description = "Vermilion host metrics and journals. Vermilion is a single-node k3s inference server with an integrated AMD GPU that shares system memory.";
      panels = [
        {
          title = "Node exporter reachable";
          type = "stat";
          expr = ''up{${node}}'';
          unit = "bool";
        }
        {
          title = "Uptime";
          type = "stat";
          expr = ''time() - node_boot_time_seconds{${node}}'';
          unit = "s";
        }
        {
          title = "CPU usage";
          expr = ''1 - avg by (instance) (rate(node_cpu_seconds_total{${node},mode="idle"}[$__rate_interval]))'';
          unit = "percentunit";
        }
        {
          title = "Memory usage";
          expr = ''1 - node_memory_MemAvailable_bytes{${node}} / node_memory_MemTotal_bytes{${node}}'';
          description = "Includes GPU allocations, because the integrated GPU maps system memory through GTT.";
          unit = "percentunit";
        }
        {
          title = "CPU, memory, and IO pressure";
          targets = [
            (target ''rate(node_pressure_cpu_waiting_seconds_total{${node}}[$__rate_interval])'' "{{instance}} CPU waiting")
            (target ''rate(node_pressure_memory_waiting_seconds_total{${node}}[$__rate_interval])'' "{{instance}} memory waiting")
            (target ''rate(node_pressure_io_waiting_seconds_total{${node}}[$__rate_interval])'' "{{instance}} IO waiting")
          ];
          description = "Fraction of time at least one task stalled on the resource.";
          unit = "percentunit";
        }
        {
          title = "Filesystem space used";
          expr = ''1 - node_filesystem_avail_bytes{${node},fstype!~"tmpfs|ramfs",mountpoint!="/nix/store"} / node_filesystem_size_bytes{${node},fstype!~"tmpfs|ramfs",mountpoint!="/nix/store"}'';
          legend = "{{instance}} {{mountpoint}}";
          description = "/, /home, and /nix are subvolumes of one Btrfs filesystem, so they report the same usage.";
          unit = "percentunit";
        }
        {
          title = "Network receive rate";
          expr = ''rate(node_network_receive_bytes_total{${node},device!~"lo|veth.*|cni0|flannel.*"}[$__rate_interval])'';
          legend = "{{instance}} {{device}}";
          description = "Physical and Tailscale interfaces. Pod-network interfaces are excluded.";
          unit = "Bps";
        }
        {
          title = "Network transmit rate";
          expr = ''rate(node_network_transmit_bytes_total{${node},device!~"lo|veth.*|cni0|flannel.*"}[$__rate_interval])'';
          legend = "{{instance}} {{device}}";
          description = "Physical and Tailscale interfaces. Pod-network interfaces are excluded.";
          unit = "Bps";
        }
        {
          title = "Disk I/O rate";
          targets = [
            (target ''rate(node_disk_read_bytes_total{${node}}[$__rate_interval])'' "{{instance}} {{device}} read")
            (target ''rate(node_disk_written_bytes_total{${node}}[$__rate_interval])'' "{{instance}} {{device}} write")
          ];
          unit = "Bps";
        }
        {
          title = "Hardware temperature";
          expr = ''node_hwmon_temp_celsius{${node}} ${chipName}'';
          legend = "{{instance}} {{chip_name}} {{sensor}}";
          unit = "celsius";
        }
        {
          title = "GPU busy";
          expr = ''node_drm_gpu_busy_percent{${node}}'';
          legend = "{{instance}} {{card}}";
          unit = "percent";
        }
        {
          title = "GPU memory used";
          targets = [
            (target ''node_drm_memory_gtt_used_bytes{${node}}'' "{{instance}} {{card}} GTT used")
            (target ''node_drm_memory_gtt_size_bytes{${node}}'' "{{instance}} {{card}} GTT size")
            (target ''node_drm_memory_vram_used_bytes{${node}}'' "{{instance}} {{card}} VRAM used")
            (target ''node_drm_memory_vram_size_bytes{${node}}'' "{{instance}} {{card}} VRAM size")
          ];
          description = "The integrated GPU has a small VRAM carve-out and holds models in GTT, which is system memory mapped for the GPU.";
          unit = "bytes";
        }
        {
          title = "GPU power";
          expr = ''node_hwmon_power_average_watt{${node}} ${chipName}'';
          legend = "{{instance}} {{chip_name}} {{sensor}}";
          description = "Average power reported by the amdgpu driver (PPT).";
          unit = "watt";
        }
        {
          title = "Failed system services";
          expr = ''sum by (instance) (node_systemd_unit_state{${node},state="failed"})'';
        }
        {
          title = "Host logs";
          type = "logs";
          datasource = loki;
          description = "System journal. Filter by unit or level in Explore.";
          expr = ''{host=~"$host",job="systemd-journal"}'';
        }
      ];
    };
    dataProtection = dashboard {
      uid = "kanto-data-protection";
      title = "Kanto data protection";
      description = "Restic completion results and Btrfs device error counters. Backup history starts when reporting is enabled. Unknown means no result is available.";
      time = {
        from = "now-7d";
        to = "now";
      };
      variables = [
        hostVariable
        (variable "backup" ''label_values(restic_backup_job_info{instance=~"$host"}, backup)'')
      ];
      panels = [
        {
          title = "Configured backup jobs";
          expr = ''sum by (instance) (restic_backup_job_info{${backup}})'';
          description = "Scheduled Restic jobs registered for reporting.";
        }
        {
          title = "Last completed backup succeeded";
          expr = ''restic_backup_last_run_success{${backup}}'';
          legend = "{{instance}} {{scope}}/{{owner}} {{backup}}";
          unit = "bool";
          description = "Result of the complete systemd backup job, including preparation, pruning, checks, and cleanup. Unknown until the first reported completion.";
        }
        {
          title = "Time since successful backup";
          expr = ''time() - restic_backup_last_success_timestamp_seconds{${backup}}'';
          legend = "{{instance}} {{scope}}/{{owner}} {{backup}}";
          unit = "s";
          description = "A failed job preserves the previous successful completion time. Unknown means no successful completion has been observed.";
        }
        {
          title = "Time since backup completion";
          expr = ''time() - restic_backup_last_completion_timestamp_seconds{${backup}}'';
          legend = "{{instance}} {{scope}}/{{owner}} {{backup}}";
          unit = "s";
        }
        {
          title = "Btrfs device error counters";
          expr = ''node_btrfs_device_errors_total{${node}}'';
          legend = "{{instance}} {{device}} {{type}}";
          description = "Persistent read, write, flush, corruption, and generation error counters from the node exporter. Vermilion does not report scrub results.";
        }
        {
          title = "Textfile collection errors";
          expr = ''node_textfile_scrape_error{${node}}'';
          description = "Nonzero means Alloy could not read or parse a metrics file, including the backup results.";
        }
      ];
    };
    kubernetes = dashboard {
      uid = "kanto-kubernetes-workloads";
      title = "Kubernetes workloads";
      variables = [
        (variable "node" ''label_values(kube_node_info{job="kube-state-metrics"}, node)'')
        (variable "namespace" ''label_values(pod_workload_info{node=~"$node"}, namespace)'')
        (variable "pod" ''label_values(pod_workload_info{node=~"$node",namespace=~"$namespace"}, pod)'')
      ];
      panels =
        [
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
            expr = ''{cluster="kanto",job!="kubernetes-events",namespace=~"$namespace",pod=~"$pod",node=~"$node"}'';
          }
          {
            title = "Kubernetes warning events";
            type = "logs";
            datasource = loki;
            expr = ''{cluster="kanto",job="kubernetes-events",namespace=~"$namespace"} | json | type="Warning"'';
          }
        ]
        ++ import ./_flux-panels.nix {inherit target;};
    };
    inference = dashboard {
      uid = "kanto-inference";
      title = "Kanto inference";
      description = "Lemonade model serving, Open WebUI traffic, and the inference services on Vermilion. Ollama and ComfyUI expose no metrics, so only their service state and logs appear.";
      panels = [
        {
          title = "Lemonade server up";
          type = "stat";
          expr = ''lemonade_server_up{${lemonade}}'';
          description = "Lemonade's own health flag, scraped by Alloy.";
          unit = "bool";
        }
        {
          title = "Inference services active";
          expr = ''node_systemd_unit_state{${node},${inferenceUnits},state="active"}'';
          legend = "{{instance}} {{name}}";
          unit = "bool";
        }
        {
          title = "Loaded models";
          type = "table";
          expr = ''lemonade_model_loaded{${lemonade}} == 1'';
          transformations = [
            {
              id = "filterFieldsByName";
              options.include.names = ["model_name" "type" "recipe" "device"];
            }
          ];
          description = "Models Lemonade currently holds in memory.";
        }
        {
          title = "Lemonade requests per second";
          expr = ''sum by (model_name) (rate(lemonade_model_requests_total{${lemonade}}[$__rate_interval]))'';
          legend = "{{model_name}}";
          unit = "reqps";
        }
        {
          title = "Lemonade tokens per second";
          targets = [
            (target ''rate(lemonade_input_tokens_total{${lemonade}}[$__rate_interval])'' "{{instance}} input")
            (target ''rate(lemonade_output_tokens_total{${lemonade}}[$__rate_interval])'' "{{instance}} output")
          ];
          description = "Token throughput across all models.";
        }
        {
          title = "Generation speed of last request";
          expr = ''lemonade_model_tokens_per_second{${lemonade}}'';
          legend = "{{model_name}}";
          description = "Output tokens per second for the most recent completed request. The value holds between requests.";
        }
        {
          title = "Time to first token of last request";
          expr = ''lemonade_model_time_to_first_token_seconds{${lemonade}}'';
          legend = "{{model_name}}";
          description = "Prompt processing time for the most recent completed request. The value holds between requests.";
          unit = "s";
        }
        {
          title = "Lemonade memory";
          targets = [
            (target ''lemonade_memory_used_gb{${lemonade}}'' "{{instance}} system memory used")
            (target ''lemonade_vram_used_gb{${lemonade}}'' "{{instance}} GPU memory used")
          ];
          description = "Host-wide usage as Lemonade reports it, in GiB. GPU memory includes GTT.";
          unit = "gbytes";
        }
        {
          title = "Open WebUI users";
          targets = [
            (target ''webui_users_active{${openWebui}}'' "active now")
            (target ''webui_users_active_today{${openWebui}}'' "active today")
            (target ''webui_users_total{${openWebui}}'' "registered")
          ];
          description = "Open WebUI pushes these over OTLP, so they are not filtered by host.";
        }
        {
          title = "Open WebUI requests by status";
          expr = ''sum by (http_status_code) (rate(http_server_requests_total{${openWebui}}[$__rate_interval]))'';
          legend = "{{http_status_code}}";
          unit = "reqps";
        }
        {
          title = "Open WebUI request duration p95";
          expr = ''histogram_quantile(0.95, sum by (le) (rate(http_server_duration_milliseconds_bucket{${openWebui}}[$__rate_interval])))'';
          legend = "p95";
          description = "Server-side HTTP duration across all routes. Streaming chat responses count until the stream ends.";
          unit = "ms";
        }
        {
          title = "Inference service logs";
          type = "logs";
          datasource = loki;
          description = "Journals of lemond, ollama, and comfyui on the host.";
          expr = ''{host=~"$host",job="systemd-journal",unit=~"lemond.service|ollama.service|comfyui.service"}'';
        }
      ];
    };
    reporting = dashboard {
      uid = "kanto-reporting-health";
      title = "Reporting health";
      panels = [
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
          expr = ''sum by (host) (count_over_time({cluster="kanto",service="observability-canary",host=~"$host"} |= "observability_canary" [5m]))'';
          legend = "{{host}}";
          description = "The host emits one heartbeat per minute. Missing heartbeats mean the host is down or log delivery has stopped.";
        }
        {
          title = "Log coverage by source";
          datasource = loki;
          expr = ''sum by (job) (rate({cluster="kanto"}[$__rate_interval]))'';
          legend = "{{job}}";
          unit = "ops";
        }
      ];
    };
  in {
    services.grafana.provision.dashboards.settings.providers = [
      {
        name = "kanto-infrastructure";
        folder = "Kanto";
        options.path = pkgs.linkFarm "kanto-dashboards" (map (item: {
          name = "${item.uid}.json";
          path = pkgs.writeText "${item.uid}.json" (builtins.toJSON item);
        }) [host dataProtection kubernetes inference reporting]);
      }
    ];
  };
}
