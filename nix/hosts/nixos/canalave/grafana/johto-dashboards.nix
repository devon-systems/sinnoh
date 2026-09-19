_: {
  flake.nixosModules.canalave = {
    config,
    lib,
    pkgs,
    ...
  }: let
    source = name: let
      datasource = lib.findFirst (item: item.name == name) null config.services.grafana.provision.datasources.settings.datasources;
    in {inherit (datasource) type uid;};
    prometheus = source "Johto Prometheus";
    links = [
      {
        type = "dashboards";
        tags = ["johto"];
        asDropdown = false;
        includeVars = true;
        keepTime = true;
        title = "Johto";
      }
    ];
    target = expr: legendFormat: {inherit expr legendFormat;};
    panel = index: specification: let
      type = specification.type or "timeseries";
      datasource = specification.datasource or prometheus;
    in {
      id = index + 1;
      inherit type datasource;
      interval = "30s";
      inherit (specification) title;
      transformations = specification.transformations or [];
      description = specification.description or "Missing telemetry is shown as Unknown. Rates account for counter resets.";
      gridPos = {
        x = lib.mod index 2 * 12;
        y = builtins.div index 2 * 8;
        w = 12;
        h = 8;
      };
      targets = lib.imap0 (queryIndex: query:
        query
        // {
          inherit datasource;
          refId = "query-${toString queryIndex}";
          editorMode = "code";
          format =
            if type == "table"
            then "table"
            else "time_series";
          instant = type == "stat" || type == "table";
          range = type == "timeseries";
          queryType =
            if type == "timeseries"
            then "range"
            else "instant";
        })
      specification.targets;
      fieldConfig = {
        defaults =
          {
            unit = specification.unit or "short";
            min = 0;
            noValue = "Unknown";
            color.mode =
              if specification ? thresholds
              then "thresholds"
              else "palette-classic";
            custom = {spanNulls = false;};
            mappings =
              (specification.mappings or [])
              ++ lib.optional ((specification.unit or "") == "bool") {
                type = "value";
                options = {
                  "0" = {
                    text = "False";
                    color = "red";
                  };
                  "1" = {
                    text = "True";
                    color = "green";
                  };
                };
              }
              ++ map (match: {
                type = "special";
                options = {
                  inherit match;
                  result = {
                    text = "Unknown";
                    color = "text";
                  };
                };
              }) ["nan" "null"];
          }
          // lib.optionalAttrs (specification ? thresholds) {
            thresholds = {
              mode = "absolute";
              steps = specification.thresholds;
            };
          };
        overrides = [];
      };
      options =
        if type == "stat"
        then {
          reduceOptions = {
            calcs = ["lastNotNull"];
            fields = "";
            values = false;
          };
          graphMode = "none";
          text = {
            titleSize = 14;
            valueSize =
              if (specification.unit or "") == "dateTimeAsIso"
              then 16
              else 32;
          };
          colorMode = "value";
        }
        else if type == "table"
        then {
          showHeader = true;
          sortBy = specification.sortBy or [];
          cellHeight = "sm";
        }
        else {
          legend = {
            displayMode = "list";
            placement = "bottom";
          };
          tooltip.mode = "multi";
        };
    };
    variable = name: query: {
      inherit name query;
      label = lib.toUpper (builtins.substring 0 1 name) + builtins.substring 1 (-1) name;
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
    };
    dashboard = uid: title: variables: panels: {
      inherit uid title links;
      description = "Johto telemetry collected every 30 seconds. Unknown means telemetry is absent, not healthy.";
      tags = ["johto"];
      schemaVersion = 39;
      version = 1;
      editable = false;
      timezone = "browser";
      refresh = "30s";
      time = {
        from =
          if uid == "johto-postgres-backups"
          then "now-7d"
          else "now-6h";
        to = "now";
      };
      templating.list = variables;
      panels = lib.imap0 panel panels;
    };
    node = ''job="node",instance=~"$node"'';
    nodeVariable = variable "node" ''label_values(up{job="node"}, instance)'';
    overview = dashboard "johto-overview" "Johto overview" [nodeVariable] [
      {
        title = "Node exporter reachable";
        type = "stat";
        targets = [(target ''up{${node}}'' "{{instance}}")];
        unit = "bool";
      }
      {
        title = "Uptime";
        type = "stat";
        targets = [(target ''time() - node_boot_time_seconds{${node}}'' "{{instance}}")];
        unit = "s";
      }
      {
        title = "CPU busy";
        targets = [(target ''1 - avg by (instance) (rate(node_cpu_seconds_total{${node},mode="idle"}[$__rate_interval]))'' "{{instance}}")];
        unit = "percentunit";
      }
      {
        title = "Available memory";
        targets = [(target ''node_memory_MemAvailable_bytes{${node}}'' "{{instance}} available") (target ''node_memory_MemTotal_bytes{${node}}'' "{{instance}} total")];
        unit = "bytes";
      }
      {
        title = "Memory cache and buffers";
        targets = [(target ''node_memory_Cached_bytes{${node}} + node_memory_Buffers_bytes{${node}} + node_memory_SReclaimable_bytes{${node}}'' "{{instance}} cache + buffers + reclaimable slab")];
        unit = "bytes";
      }
      {
        title = "Swap used";
        targets = [(target ''node_memory_SwapTotal_bytes{${node}} - node_memory_SwapFree_bytes{${node}}'' "{{instance}}")];
        unit = "bytes";
      }
      {
        title = "Memory pressure";
        targets = [(target ''rate(node_pressure_memory_waiting_seconds_total{${node}}[$__rate_interval])'' "{{instance}} some stalled") (target ''rate(node_pressure_memory_stalled_seconds_total{${node}}[$__rate_interval])'' "{{instance}} all stalled")];
        unit = "percentunit";
      }
      {
        title = "Filesystem capacity used";
        targets = [(target ''1 - node_filesystem_avail_bytes{${node},fstype!~"tmpfs|devtmpfs|overlay|squashfs",mountpoint!~"/var/lib/kubelet/.*"} / node_filesystem_size_bytes{${node},fstype!~"tmpfs|devtmpfs|overlay|squashfs",mountpoint!~"/var/lib/kubelet/.*"}'' "{{instance}} {{mountpoint}}")];
        unit = "percentunit";
      }
      {
        title = "Disk reads and writes";
        targets = [(target ''rate(node_disk_read_bytes_total{${node},device!~"loop.*|ram.*"}[$__rate_interval])'' "{{instance}} {{device}} read") (target ''rate(node_disk_written_bytes_total{${node},device!~"loop.*|ram.*"}[$__rate_interval])'' "{{instance}} {{device}} write")];
        unit = "Bps";
      }
      {
        title = "Disk busy";
        targets = [(target ''rate(node_disk_io_time_seconds_total{${node},device!~"loop.*|ram.*"}[$__rate_interval])'' "{{instance}} {{device}}")];
        unit = "percentunit";
      }
      {
        title = "Network traffic";
        targets = [(target ''rate(node_network_receive_bytes_total{${node},device!~"lo|veth.*|cali.*"}[$__rate_interval])'' "{{instance}} {{device}} receive") (target ''rate(node_network_transmit_bytes_total{${node},device!~"lo|veth.*|cali.*"}[$__rate_interval])'' "{{instance}} {{device}} transmit")];
        unit = "Bps";
      }
      {
        title = "Failed systemd services";
        type = "stat";
        targets = [(target ''sum by (instance) (node_systemd_unit_state{${node},state="failed",name=~".+[.]service"})'' "{{instance}}")];
      }

      {
        title = "Cherrygrove service";
        type = "stat";
        unit = "short";
        targets = [(target ''node_systemd_unit_state{job="node",instance="goldenrod",name="microvm@cherrygrove.service",state=~"active|failed"}'' "{{state}}")];
        description = "Observed only through Goldenrod systemd. No collection inside the VM.";
      }

      {
        title = "Collector health";
        type = "table";
        transformations = [
          {
            id = "filterFieldsByName";
            options.include.names = ["instance" "collector" "Value"];
          }
        ];
        unit = "bool";
        targets = [(target ''node_scrape_collector_success{${node}}'' "{{instance}} {{collector}}")];
      }

      {
        title = "CPU and IO pressure";
        type = "timeseries";
        unit = "percentunit";
        targets = [
          (target ''rate(node_pressure_cpu_waiting_seconds_total{${node}}[$__rate_interval])'' "{{instance}} CPU waiting")
          (target ''rate(node_pressure_io_waiting_seconds_total{${node}}[$__rate_interval])'' "{{instance}} IO waiting")
          (target ''rate(node_pressure_io_stalled_seconds_total{${node}}[$__rate_interval])'' "{{instance}} IO stalled")
        ];
      }
    ];
    selectedPods = ''johto_pod_workload_info{node=~"$node",namespace=~"$namespace",workload=~"$workload",pod=~"$pod"}'';
    container = ''job="cadvisor",container!="",container!="POD",image!="",namespace=~"$namespace",pod=~"$pod",node=~"$node"'';
    joinPods = expression: "(${expression}) * on (namespace, pod) group_left(workload, workload_kind) ${selectedPods}";
    kubeContainer = ''job="kube-state-metrics",namespace=~"$namespace",pod=~"$pod"'';
    workloadVariable = variable "workload" ''label_values(johto_pod_workload_info{node=~"$node",namespace=~"$namespace"}, workload)'';
    workloads =
      dashboard "johto-kubernetes-workloads" "Kubernetes workloads" [
        (variable "node" ''label_values(kube_node_info{job="kube-state-metrics"}, node)'')
        (variable "namespace" ''label_values(johto_pod_workload_info{node=~"$node"}, namespace)'')
        workloadVariable
        (variable "pod" ''label_values(johto_pod_workload_info{node=~"$node",namespace=~"$namespace",workload=~"$workload"}, pod)'')
      ] ([
          {
            title = "Collector scrape health";
            type = "stat";
            targets = [(target ''up{job=~"cadvisor|kube-state-metrics"}'' "{{job}} {{node}}") (target ''sum(up{job="cadvisor"}) == bool 2'' "Both kubelets reachable") (target ''kube_node_status_condition{job="kube-state-metrics",node=~"$node",condition="Ready",status="true"}'' "{{node}} Ready")];
            unit = "bool";
          }
          {
            title = "Pod placement";
            type = "table";
            transformations = [
              {
                id = "filterFieldsByName";
                options.include.names = ["namespace" "workload" "pod" "node"];
              }
            ];
            targets = [(target selectedPods "{{namespace}} / {{workload_kind}} {{workload}} / {{pod}} on {{node}}")];
            description = "One series per pod. ReplicaSet ownership resolves to its Deployment; Jobs remain individually selectable.";
          }
          {
            title = "Container CPU consumption";
            unit = "cores";
            targets = [(target (joinPods ''sum by (namespace, pod, container) (rate(container_cpu_usage_seconds_total{${container}}[$__rate_interval]))'') "{{namespace}} / {{pod}} / {{container}}")];
          }
          {
            title = "CPU throttled periods";
            unit = "percentunit";
            targets = [(target (joinPods ''sum by (namespace, pod, container) (rate(container_cpu_cfs_throttled_periods_total{${container}}[$__rate_interval])) / sum by (namespace, pod, container) (rate(container_cpu_cfs_periods_total{${container}}[$__rate_interval]))'') "{{pod}} / {{container}}")];
            description = "Fraction of CFS periods throttled. An unset CPU limit may have no CFS series.";
          }
          {
            title = "Memory working set";
            unit = "bytes";
            targets = [(target (joinPods ''sum by (namespace, pod, container) (container_memory_working_set_bytes{${container}})'') "{{pod}} / {{container}}")];
            description = "cAdvisor working set excludes inactive file cache. It is distinct from RSS.";
          }
          {
            title = "Memory RSS";
            unit = "bytes";
            targets = [(target (joinPods ''sum by (namespace, pod, container) (container_memory_rss{${container}})'') "{{pod}} / {{container}}")];
            description = "Resident anonymous and swap-cache memory as reported by cAdvisor, separate from working set.";
          }
        ]
        ++ lib.concatMap (resource: [
          {
            title = "Container ${resource} requests";
            unit =
              if resource == "cpu"
              then "cores"
              else "bytes";
            targets = [(target (joinPods ''kube_pod_container_resource_requests{${kubeContainer},resource="${resource}"}'') "{{pod}} / {{container}}")];
          }
          {
            title = "Container ${resource} limits";
            type = "table";
            transformations = [
              {
                id = "filterFieldsByName";
                options.include.names = ["namespace" "pod" "container" "Value"];
              }
            ];
            unit =
              if resource == "cpu"
              then "cores"
              else "bytes";
            targets = [(target (joinPods ''kube_pod_container_resource_limits{${kubeContainer},resource="${resource}"} or on (namespace, pod, container) (0 * kube_pod_container_info{${kubeContainer}} - 1)'') "{{pod}} / {{container}}")];
            mappings = [
              {
                type = "value";
                options."-1" = {
                  text = "Unset";
                  color = "text";
                };
              }
            ];
            description = "Unset means kube-state-metrics reports the container without this resource limit. Missing telemetry remains Unknown.";
          }
          {
            title = "Node allocatable ${resource} and all container requests";
            unit =
              if resource == "cpu"
              then "cores"
              else "bytes";
            targets = [(target ''kube_node_status_allocatable{job="kube-state-metrics",node=~"$node",resource="${resource}"}'' "{{node}} allocatable") (target ''sum by (node) (kube_pod_container_resource_requests{job="kube-state-metrics",node=~"$node",resource="${resource}"} and on(namespace,pod) (kube_pod_status_phase{job="kube-state-metrics",phase=~"Running|Pending"} == 1))'' "{{node}} requested")];
            description = "Node-wide totals ignore namespace, workload and pod filters. Container requests exclude pod overhead and init-container scheduling rules.";
          }
        ]) ["cpu" "memory"]
        ++ [
          {
            title = "Container restarts in selected range";
            targets = [(target (joinPods ''increase(kube_pod_container_status_restarts_total{${kubeContainer}}[$__range])'') "{{pod}} / {{container}}")];
          }
          {
            title = "OOM events in selected range";
            targets = [(target (joinPods ''sum by (namespace, pod, container) (increase(container_oom_events_total{${container}}[$__range]))'') "{{pod}} / {{container}}")];
          }
          {
            title = "Last termination was OOMKilled";
            type = "stat";
            targets = [(target (joinPods ''kube_pod_container_status_last_terminated_reason{${kubeContainer},reason="OOMKilled"}'') "{{pod}} / {{container}}")];
            description = "Last known termination reason, not an event count. No termination history shows Unknown.";
          }
          {
            title = "Container readiness";
            type = "stat";
            unit = "bool";
            targets = [(target (joinPods ''kube_pod_container_status_ready{${kubeContainer}}'') "{{pod}} / {{container}}")];
          }
          {
            title = "Desired and available deployment replicas";
            targets = [(target ''kube_deployment_spec_replicas{job="kube-state-metrics",namespace=~"$namespace",deployment=~"$workload"}'' "{{namespace}} / {{deployment}} desired") (target ''kube_deployment_status_replicas_available{job="kube-state-metrics",namespace=~"$namespace",deployment=~"$workload"}'' "{{namespace}} / {{deployment}} available")];
            description = "Controller totals follow namespace and workload filters, including controllers with zero pods. Node and pod filters do not restrict these totals.";
          }
          {
            title = "StatefulSet and DaemonSet replicas";
            targets = [(target ''kube_statefulset_replicas{job="kube-state-metrics",namespace=~"$namespace",statefulset=~"$workload"}'' "{{statefulset}} desired") (target ''kube_statefulset_status_replicas_ready{job="kube-state-metrics",namespace=~"$namespace",statefulset=~"$workload"}'' "{{statefulset}} ready") (target ''kube_daemonset_status_desired_number_scheduled{job="kube-state-metrics",namespace=~"$namespace",daemonset=~"$workload"}'' "{{daemonset}} desired") (target ''kube_daemonset_status_number_available{job="kube-state-metrics",namespace=~"$namespace",daemonset=~"$workload"}'' "{{daemonset}} available")];
            description = "Controller totals follow namespace and workload filters; node and pod filters do not apply.";
          }
          {
            title = "Job outcomes";
            targets = [(target ''kube_job_status_succeeded{job="kube-state-metrics",namespace=~"$namespace",job_name=~"$workload"}'' "{{job_name}} succeeded") (target ''kube_job_status_failed{job="kube-state-metrics",namespace=~"$namespace",job_name=~"$workload"}'' "{{job_name}} failed")];
          }
          {
            title = "CronJob last successful completion";
            type = "stat";
            unit = "dateTimeAsIso";
            targets = [(target ''kube_cronjob_status_last_successful_time{job="kube-state-metrics",namespace=~"$namespace"} * 1000'' "{{namespace}} / {{cronjob}}")];
            description = "Namespace-wide CronJobs, including those with no current pods. Missing completion remains Unknown.";
          }

          {
            title = "Flux readiness";
            type = "table";
            unit = "short";
            targets = [(target ''gotk_resource_info{job="kube-state-metrics",exported_namespace=~"$namespace"}'' "{{customresource_kind}} {{name}} {{controller}}")];
            description = "Flux panels follow namespace only. Readiness and suspension come from resource state; missing state remains Unknown.";
          }

          {
            title = "Flux suspended resources";
            type = "table";
            unit = "short";
            targets = [(target ''gotk_resource_info{job="kube-state-metrics",exported_namespace=~"$namespace",suspended="true"}'' "{{customresource_kind}} {{name}} {{controller}}")];
            description = "Flux panels follow namespace only. Readiness and suspension come from resource state; missing state remains Unknown.";
          }

          {
            title = "Flux pending generations";
            type = "stat";
            unit = "short";
            targets = [(target ''clamp_min(gotk_resource_generation{job="kube-state-metrics",exported_namespace=~"$namespace"} - gotk_resource_observed_generation{job="kube-state-metrics",exported_namespace=~"$namespace"}, 0)'' "{{customresource_kind}} {{name}} {{controller}}")];
            description = "Flux panels follow namespace only. Readiness and suspension come from resource state; missing state remains Unknown.";
          }

          {
            title = "Flux reconciliation failures";
            type = "timeseries";
            unit = "short";
            targets = [(target ''sum by (controller) (increase(controller_runtime_reconcile_total{job="flux",result="error"}[$__range]))'' "{{customresource_kind}} {{name}} {{controller}}")];
            description = "Flux panels follow namespace only. Readiness and suspension come from resource state; missing state remains Unknown.";
          }

          {
            title = "Flux reconciliation duration p95";
            type = "timeseries";
            unit = "s";
            targets = [(target ''histogram_quantile(0.95, sum by (le,kind,name,namespace) (rate(gotk_reconcile_duration_seconds_bucket{job="flux",namespace=~"$namespace"}[$__rate_interval])))'' "{{customresource_kind}} {{name}} {{controller}}")];
            description = "Flux panels follow namespace only. Readiness and suspension come from resource state; missing state remains Unknown.";
          }
        ]);
    pg = ''job="pg-shared"'';
    backup = ''job="node",instance=~"$node"'';
    backupAge = [
      {
        color = "green";
        value = null;
      }
      {
        color = "orange";
        value = 100800;
      }
      {
        color = "red";
        value = 172800;
      }
    ];
    backups = dashboard "johto-postgres-backups" "Postgres and backups" [nodeVariable] [
      {
        title = "Postgres scrape and database health";
        type = "stat";
        unit = "bool";
        targets = [(target ''up{${pg}}'' "{{pod}} scrape") (target ''sum(up{${pg}}) == bool 1'' "Postgres instance reachable") (target ''cnpg_collector_up{${pg}}'' "{{pod}} database") (target ''1 - cnpg_collector_last_collection_error{${pg}}'' "{{pod}} collection healthy")];
        description = "Scrape, database, and collection health should all be true. Missing instances are not healthy.";
      }
      {
        title = "Primary and replica roles";
        type = "stat";
        targets = [(target ''cnpg_pg_replication_in_recovery{${pg}}'' "{{pod}}")];
        mappings = [
          {
            type = "value";
            options = {
              "0".text = "Primary";
              "1".text = "Replica";
            };
          }
        ];
      }
      {
        title = "Connections by database";
        targets = [(target ''sum by (pod, datname) (cnpg_backends_total{${pg}})'' "{{pod}} / {{datname}}")];
      }
      {
        title = "Database sizes";
        unit = "bytes";
        targets = [(target ''cnpg_pg_database_size_bytes{${pg}}'' "{{pod}} / {{datname}}")];
      }
      {
        title = "Replication";
        type = "stat";
        targets = [(target ''0 * cnpg_collector_up{${pg}}'' "pg-shared") (target ''0 * pg_up{job="immich-postgres"}'' "Immich")];
        mappings = [
          {
            type = "value";
            options."0".text = "Not configured";
          }
        ];
        description = "Both Johto databases have one instance. Replication is not configured.";
      }
      {
        title = "WAL archiving outcomes";
        unit = "ops";
        targets = [(target ''rate(cnpg_pg_stat_archiver_archived_count{${pg}}[$__rate_interval])'' "{{pod}} archived/s") (target ''rate(cnpg_pg_stat_archiver_failed_count{${pg}}[$__rate_interval])'' "{{pod}} failed/s")];
      }
      {
        title = "Last WAL archive age";
        unit = "s";
        targets = [(target ''time() - (cnpg_pg_stat_archiver_last_archived_time{${pg}} > 0)'' "{{pod}}")];
      }
      {
        title = "Latest available database backup";
        type = "stat";
        unit = "dateTimeAsIso";
        targets = [(target ''(barman_cloud_cloudnative_pg_io_last_available_backup_timestamp{${pg}} > 0) * 1000'' "{{pod}}")];
      }
      {
        title = "Latest failed database backup";
        type = "stat";
        unit = "dateTimeAsIso";
        targets = [(target ''barman_cloud_cloudnative_pg_io_last_failed_backup_timestamp{${pg}} * 1000'' "{{pod}}")];
        mappings = [
          {
            type = "value";
            options."0".text = "No recorded failure";
          }
        ];
      }
      {
        title = "Database backup age";
        type = "stat";
        unit = "s";
        thresholds = backupAge;
        targets = [(target ''time() - (barman_cloud_cloudnative_pg_io_last_available_backup_timestamp{${pg}} > 0)'' "{{pod}}")];
      }
      {
        title = "Recovery-window start";
        type = "stat";
        unit = "dateTimeAsIso";
        targets = [(target ''(barman_cloud_cloudnative_pg_io_first_recoverability_point{${pg}} > 0) * 1000'' "{{pod}}")];
        description = "Earliest recoverable point reported by the Barman plugin. Backup availability does not prove a successful restore.";
      }
      {
        title = "Host backup inventory";
        type = "table";
        transformations = [
          {
            id = "filterFieldsByName";
            options.include.names = ["instance" "backup" "Value"];
          }
        ];
        sortBy = [
          {
            displayName = "backup";
            desc = false;
          }
        ];
        targets = [(target ''johto_backup_job_info{${backup}}'' "{{instance}} / {{backup}}")];
        description = "Derived from every configured restic job. Includes all 16 configured Goldenrod and Olivine jobs.";
      }
      {
        title = "Host backup reporting health";
        type = "stat";
        unit = "bool";
        targets = [(target ''up{${backup}}'' "{{instance}} exporter reachable") (target ''1 - node_textfile_scrape_error{${backup}}'' "{{instance}} textfile healthy")];
        description = "Exporter reachable and textfile healthy should both be true. The node selector applies only to host backup panels.";
      }
      {
        title = "Host backup age since last success";
        type = "table";
        transformations = [
          {
            id = "filterFieldsByName";
            options.include.names = ["instance" "backup" "Value"];
          }
        ];
        sortBy = [
          {
            displayName = "backup";
            desc = false;
          }
        ];
        unit = "s";
        thresholds = backupAge;
        targets = [(target ''time() - johto_backup_last_success_timestamp_seconds{${backup}}'' "{{instance}} / {{backup}}")];
        description = "Warning after 28 hours, critical after 48 hours. Unknown until a successful completion is observed or seeded from systemd.";
      }
      {
        title = "Host backup latest outcome";
        type = "table";
        transformations = [
          {
            id = "filterFieldsByName";
            options.include.names = ["instance" "backup" "Value"];
          }
        ];
        sortBy = [
          {
            displayName = "backup";
            desc = false;
          }
        ];
        targets = [(target ''johto_backup_last_run_success{${backup}}'' "{{instance}} / {{backup}}")];
        mappings = [
          {
            type = "value";
            options = {
              "0" = {
                text = "Failed";
                color = "red";
              };
              "1" = {
                text = "Succeeded";
                color = "green";
              };
            };
          }
        ];
        description = "Latest completion outcome, separate from backup age. Interrupted runs count as failures; prior success is preserved.";
      }
      {
        title = "Host backup last completion";
        type = "table";
        transformations = [
          {
            id = "filterFieldsByName";
            options.include.names = ["instance" "backup" "Value"];
          }
        ];
        sortBy = [
          {
            displayName = "backup";
            desc = false;
          }
        ];
        unit = "dateTimeAsIso";
        targets = [(target ''johto_backup_last_completion_timestamp_seconds{${backup}} * 1000'' "{{instance}} / {{backup}}")];
      }
      {
        title = "Host backup last success";
        type = "table";
        transformations = [
          {
            id = "filterFieldsByName";
            options.include.names = ["instance" "backup" "Value"];
          }
        ];
        sortBy = [
          {
            displayName = "backup";
            desc = false;
          }
        ];
        unit = "dateTimeAsIso";
        targets = [(target ''johto_backup_last_success_timestamp_seconds{${backup}} * 1000'' "{{instance}} / {{backup}}")];
      }

      {
        title = "Immich Postgres health";
        type = "stat";
        unit = "bool";
        targets = [(target ''pg_up{job="immich-postgres"}'' "{{datname}} {{mode}}")];
        description = "Immich uses database-dump recovery. Files are backed up after the database dump while applications remain online; there is no WAL recovery window.";
      }

      {
        title = "Immich connections";
        type = "timeseries";
        unit = "short";
        targets = [(target ''pg_stat_database_numbackends{job="immich-postgres"}'' "{{datname}} {{mode}}")];
        description = "Immich uses database-dump recovery. Files are backed up after the database dump while applications remain online; there is no WAL recovery window.";
      }

      {
        title = "Immich database sizes";
        type = "timeseries";
        unit = "bytes";
        targets = [(target ''pg_database_size_bytes{job="immich-postgres"}'' "{{datname}} {{mode}}")];
        description = "Immich uses database-dump recovery. Files are backed up after the database dump while applications remain online; there is no WAL recovery window.";
      }

      {
        title = "Immich transactions";
        type = "timeseries";
        unit = "ops";
        targets = [(target ''rate(pg_stat_database_xact_commit{job="immich-postgres"}[$__rate_interval])'' "{{datname}} {{mode}}")];
        description = "Immich uses database-dump recovery. Files are backed up after the database dump while applications remain online; there is no WAL recovery window.";
      }

      {
        title = "Immich locks";
        type = "timeseries";
        unit = "short";
        targets = [(target ''pg_locks_count{job="immich-postgres"}'' "{{datname}} {{mode}}")];
        description = "Immich uses database-dump recovery. Files are backed up after the database dump while applications remain online; there is no WAL recovery window.";
      }

      {
        title = "pg-shared transactions";
        type = "timeseries";
        unit = "ops";
        targets = [(target ''rate(cnpg_pg_stat_database_xact_commit{${pg}}[$__rate_interval])'' "{{datname}} {{mode}}")];
      }

      {
        title = "pg-shared waiting backends";
        type = "timeseries";
        unit = "short";
        targets = [(target ''cnpg_backends_waiting_total{${pg}}'' "{{datname}} {{mode}}")];
      }

      {
        title = "pg-shared deadlocks";
        type = "timeseries";
        unit = "ops";
        targets = [(target ''rate(cnpg_pg_stat_database_deadlocks{${pg}}[$__rate_interval])'' "{{datname}} {{mode}}")];
      }

      {
        title = "Immich validated database dump age";
        type = "stat";
        unit = "s";
        targets = [(target ''time() - johto_immich_dump_timestamp_seconds{job="node",instance="goldenrod"}'' "{{datname}} {{mode}}")];
        description = "Immich uses database-dump recovery. Files are backed up after the database dump while applications remain online; there is no WAL recovery window.";
        thresholds = backupAge;
      }

      {
        title = "Immich offsite backup age";
        type = "stat";
        unit = "s";
        targets = [(target ''time() - johto_backup_last_success_timestamp_seconds{job="node",instance="goldenrod",backup="immich"}'' "{{datname}} {{mode}}")];
        description = "Immich uses database-dump recovery. Files are backed up after the database dump while applications remain online; there is no WAL recovery window.";
        thresholds = backupAge;
      }
    ];
    storage = dashboard "johto-storage" "Storage and disks" [nodeVariable (variable "disk" ''label_values(node_disk_info{${node}}, device)'') (variable "mountpoint" ''label_values(node_filesystem_size_bytes{${node},mountpoint!~"/var/lib/kubelet/.*"}, mountpoint)'')] [
      {
        title = "Data and Media used capacity";
        type = "stat";
        unit = "percentunit";
        targets = [(target ''1 - max by (instance,mountpoint) (node_filesystem_avail_bytes{${node},mountpoint=~"/mnt/(Data|Media)"}) / max by (instance,mountpoint) (node_filesystem_size_bytes{${node},mountpoint=~"/mnt/(Data|Media)"})'' "{{instance}} {{mountpoint}}")];
        description = "Filesystem capacity is counted once per mountpoint, never summed across physical disks. Disk filters apply to physical disk panels only.";
      }

      {
        title = "Filesystem available bytes";
        type = "timeseries";
        unit = "bytes";
        targets = [(target ''max by (instance,mountpoint) (node_filesystem_avail_bytes{${node},mountpoint=~"$mountpoint",fstype!~"tmpfs|devtmpfs|overlay|squashfs",mountpoint!~"/var/lib/kubelet/.*"})'' "{{instance}} {{mountpoint}}")];
      }

      {
        title = "Filesystem capacity";
        type = "timeseries";
        unit = "bytes";
        targets = [(target ''max by (instance,mountpoint) (node_filesystem_size_bytes{${node},mountpoint=~"$mountpoint",fstype!~"tmpfs|devtmpfs|overlay|squashfs",mountpoint!~"/var/lib/kubelet/.*"})'' "{{instance}} {{mountpoint}}")];
        description = "Filesystem capacity is counted once per mountpoint, never summed across physical disks. Disk filters apply to physical disk panels only.";
      }

      {
        title = "Disk read bytes";
        type = "timeseries";
        unit = "Bps";
        targets = [(target ''rate(node_disk_read_bytes_total{${node},device=~"$disk"}[$__rate_interval])'' "{{instance}} {{device}}")];
      }

      {
        title = "Disk write bytes";
        type = "timeseries";
        unit = "Bps";
        targets = [(target ''rate(node_disk_written_bytes_total{${node},device=~"$disk"}[$__rate_interval])'' "{{instance}} {{device}}")];
      }

      {
        title = "Disk busy";
        type = "timeseries";
        unit = "percentunit";
        targets = [(target ''rate(node_disk_io_time_seconds_total{${node},device=~"$disk"}[$__rate_interval])'' "{{instance}} {{device}}")];
      }

      {
        title = "SMART health";
        type = "stat";
        unit = "bool";
        targets = [(target ''smartctl_device_smart_status{job="smartctl",instance=~"$node",device=~"$disk"}'' "{{device}}")];
      }

      {
        title = "Disk temperatures";
        type = "timeseries";
        unit = "celsius";
        targets = [(target ''smartctl_device_temperature{job="smartctl",instance=~"$node",device=~"$disk"}'' "{{device}} {{temperature_type}}")];
      }

      {
        title = "NVMe percentage used";
        type = "stat";
        unit = "percent";
        targets = [(target ''smartctl_device_percentage_used{job="smartctl",instance=~"$node",device=~"$disk"}'' "{{device}}")];
      }

      {
        title = "SATA SSD life remaining";
        type = "stat";
        unit = "percent";
        targets = [(target ''smartctl_device_attribute{job="smartctl",instance=~"$node",device=~"$disk",attribute_name="Percent_Lifetime_Remain",attribute_value_type="value"}'' "{{device}}")];
      }

      {
        title = "Btrfs device errors";
        type = "timeseries";
        unit = "short";
        targets = [(target ''node_btrfs_device_errors_total{${node}}'' "{{instance}} {{btrfs_dev_uuid}} {{type}}")];
      }

      {
        title = "Scrub age";
        type = "stat";
        unit = "s";
        targets = [(target ''time() - johto_btrfs_scrub_completion_timestamp_seconds{${node}}'' "{{filesystem}} device {{device}}")];
        thresholds = [
          {
            color = "green";
            value = null;
          }
          {
            color = "orange";
            value = 3024000;
          }
          {
            color = "red";
            value = 3888000;
          }
        ];
      }

      {
        title = "Scrub outcome";
        type = "stat";
        unit = "bool";
        targets = [(target ''johto_btrfs_scrub_success{${node}}'' "{{filesystem}} device {{device}}")];
      }

      {
        title = "Scrub errors";
        type = "stat";
        unit = "short";
        targets = [(target ''johto_btrfs_scrub_errors{${node}}'' "{{filesystem}} device {{device}}")];
      }

      {
        title = "NFS server activity";
        type = "timeseries";
        unit = "ops";
        targets = [(target ''rate(node_nfsd_requests_total{${node}}[$__rate_interval])'' "{{instance}} {{method}}")];
      }

      {
        title = "NFS errors and retransmissions";
        type = "timeseries";
        unit = "ops";
        targets = [(target ''rate({__name__=~"node_nfsd_rpc_errors_total|node_nfs_rpc_retransmissions_total",${node}}[$__rate_interval])'' "{{instance}} {{__name__}}")];
      }
    ];
    media = dashboard "johto-media-services" "Media services" [(variable "application" ''label_values(exportarr_app_info, job)'')] [
      {
        title = "Exporter health";
        type = "stat";
        unit = "bool";
        targets = [(target ''up{job=~"$application",job=~"sonarr|radarr|lidarr|prowlarr|bazarr"}'' "{{job}}")];
      }

      {
        title = "Application health";
        type = "stat";
        unit = "bool";
        targets = [(target ''{__name__=~"(sonarr|radarr|lidarr|prowlarr|bazarr)_system_status",job=~"$application"}'' "{{job}}")];
      }

      {
        title = "Health issues";
        type = "timeseries";
        unit = "short";
        targets = [(target ''{__name__=~"(sonarr|radarr|lidarr|prowlarr|bazarr)_system_health_issues",job=~"$application"}'' "{{job}} {{message}}")];
      }

      {
        title = "Sonarr queue";
        type = "stat";
        unit = "short";
        targets = [(target ''sum by(job) (sonarr_queue_total{job=~"$application"}) or on(job) (0 * (sonarr_system_status{job=~"$application"} == 1) and on(job) (up{job="sonarr"} == 1) unless on(job) (increase(sonarr_scrape_requests_total{code!~"2.."}[2m]) > 0))'' "{{job}}")];
        description = "An absent queue is zero only with current successful application telemetry and no recent failed requests.";
      }

      {
        title = "Radarr queue";
        type = "stat";
        unit = "short";
        targets = [(target ''sum by(job) (radarr_queue_total{job=~"$application"}) or on(job) (0 * (radarr_system_status{job=~"$application"} == 1) and on(job) (up{job="radarr"} == 1) unless on(job) (increase(radarr_scrape_requests_total{code!~"2.."}[2m]) > 0))'' "{{job}}")];
        description = "An absent queue is zero only with current successful application telemetry and no recent failed requests.";
      }

      {
        title = "Lidarr queue";
        type = "stat";
        unit = "short";
        targets = [(target ''sum by(job) (lidarr_queue_total{job=~"$application"}) or on(job) (0 * (lidarr_system_status{job=~"$application"} == 1) and on(job) (up{job="lidarr"} == 1) unless on(job) (increase(lidarr_scrape_requests_total{code!~"2.."}[2m]) > 0))'' "{{job}}")];
        description = "An absent queue is zero only with current successful application telemetry and no recent failed requests.";
      }

      {
        title = "Library totals";
        type = "timeseries";
        unit = "short";
        targets = [(target ''{__name__=~"sonarr_series_total|sonarr_episode_total|radarr_movie_total|lidarr_artists_total|lidarr_albums_total|lidarr_songs_total",job=~"$application"}'' "{{job}} {{__name__}} {{indexer}} {{language}}")];
      }

      {
        title = "Missing content and subtitles";
        type = "timeseries";
        unit = "short";
        targets = [(target ''{__name__=~"sonarr_episode_missing_total|radarr_movie_missing_total|lidarr_albums_missing_total|bazarr_(movie_)?subtitles_missing_total",job=~"$application"}'' "{{job}} {{__name__}} {{indexer}} {{language}}")];
      }

      {
        title = "Indexer availability";
        type = "timeseries";
        unit = "short";
        targets = [(target ''{__name__=~"prowlarr_indexer_enabled_total|prowlarr_indexer_unavailable",job=~"$application"}'' "{{job}} {{__name__}} {{indexer}} {{language}}")];
      }

      {
        title = "Indexer response times";
        type = "timeseries";
        unit = "ms";
        targets = [(target ''{__name__=~"prowlarr_indexer_average_response_time_ms",job=~"$application"}'' "{{job}} {{__name__}} {{indexer}} {{language}}")];
      }

      {
        title = "Indexer failures in application history";
        type = "timeseries";
        unit = "short";
        targets = [(target ''{__name__=~"prowlarr_indexer_failed_(queries|auth_queries|grabs|rss_queries)_total",job=~"$application"}'' "{{job}} {{__name__}} {{indexer}} {{language}}")];
      }

      {
        title = "Collection duration";
        type = "timeseries";
        unit = "s";
        targets = [(target ''{__name__=~"(sonarr|radarr|lidarr|prowlarr|bazarr)_scrape_duration_seconds",job=~"$application"}'' "{{job}} {{__name__}} {{indexer}} {{language}}")];
      }

      {
        title = "Application request failures";
        type = "timeseries";
        unit = "ops";
        targets = [(target ''sum by(job,code) (rate({__name__=~"(sonarr|radarr|lidarr|prowlarr|bazarr)_scrape_requests_total",job=~"$application",code!~"2.."}[$__rate_interval]))'' "{{job}} {{code}}")];
      }
    ];
  in {
    services.grafana.provision.dashboards.settings.providers = [
      {
        name = "johto-infrastructure";
        folder = "Johto";
        options.path = pkgs.linkFarm "johto-dashboards" (map (item: {
          name = "${item.uid}.json";
          path = pkgs.writeText "${item.uid}.json" (builtins.toJSON item);
        }) [overview storage workloads backups media]);
      }
    ];
  };
}
