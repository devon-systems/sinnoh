_: {
  flake.nixosModules.canalave = {pkgs, ...}: let
    alert = {
      name,
      expr,
      duration,
      severity,
      summary,
      description,
      labels ? {},
    }: {
      alert = name;
      inherit expr;
      for = duration;
      labels =
        {
          cluster = "sinnoh";
          inherit severity;
        }
        // labels;
      annotations = {inherit summary description;};
    };
    serviceRequests = ''traefik_router_requests_total{job="traefik",service=~"(slingshot|skytrace)-.*@kubernetes"}'';
    serviceTraffic = "sum by (service) (increase(${serviceRequests}[5m])) >= 50";
    serviceBuckets = ''traefik_service_request_duration_seconds_bucket{job="traefik",service=~"(slingshot|skytrace)-.*@kubernetes",code="200"}'';
    serviceSuccesses = ''traefik_service_request_duration_seconds_count{job="traefik",service=~"(slingshot|skytrace)-.*@kubernetes",code="200"}'';
    filesystems = ''job="node",fstype!~"tmpfs|ramfs|devtmpfs|overlay|squashfs|nsfs",mountpoint!~"/(run|var/lib/kubelet)(/.*)?"'';
    postgresBackupSuccess = ''max by (namespace) (barman_cloud_cloudnative_pg_io_last_available_backup_timestamp{job="pg-shared"})'';
    postgresBackupFailure = ''max by (namespace) (barman_cloud_cloudnative_pg_io_last_failed_backup_timestamp{job="pg-shared"})'';
  in {
    services.prometheus.ruleFiles = [
      (pkgs.writeText "sinnoh-alert-rules.json" (builtins.toJSON {
        groups = [
          {
            name = "sinnoh-alerts";
            interval = "30s";
            rules =
              [
                (alert {
                  name = "NodeDown";
                  expr = ''up{job="node"} == 0'';
                  duration = "2m";
                  severity = "critical";
                  summary = "A Sinnoh node exporter is unreachable";
                  description = "Prometheus has failed to scrape this node for two minutes. Check the host, private network, and exporter.";
                })
                (alert {
                  name = "NodeMemoryLow";
                  expr = ''node_memory_MemAvailable_bytes{job="node"} / node_memory_MemTotal_bytes{job="node"} < 0.10'';
                  duration = "15m";
                  severity = "warning";
                  summary = "A Sinnoh node has little available memory";
                  description = "Available host memory has stayed below 10% for 15 minutes. Review workload allocations and memory growth.";
                })
                (alert {
                  name = "NodeDiskSpaceLow";
                  expr = ''
                    (node_filesystem_avail_bytes{${filesystems}} / node_filesystem_size_bytes{${filesystems}} < 0.10)
                    and (node_filesystem_readonly{${filesystems}} == 0)
                  '';
                  duration = "15m";
                  severity = "warning";
                  summary = "A Sinnoh filesystem is running low on space";
                  description = "{{ $labels.instance }} {{ $labels.mountpoint }} has less than 10% available space for 15 minutes. Check database, container, log, and backup growth.";
                })
                (alert {
                  name = "NodeDiskSpaceCritical";
                  expr = ''
                    (node_filesystem_avail_bytes{${filesystems}} / node_filesystem_size_bytes{${filesystems}} < 0.05)
                    and (node_filesystem_readonly{${filesystems}} == 0)
                  '';
                  duration = "5m";
                  severity = "critical";
                  summary = "A Sinnoh filesystem is almost full";
                  description = "{{ $labels.instance }} {{ $labels.mountpoint }} has less than 5% available space for five minutes. Free space before writes and services fail.";
                })
                (alert {
                  name = "NodeInodesLow";
                  expr = ''
                    (node_filesystem_files_free{${filesystems}} / node_filesystem_files{${filesystems}} < 0.10)
                    and (node_filesystem_readonly{${filesystems}} == 0)
                  '';
                  duration = "15m";
                  severity = "warning";
                  summary = "A Sinnoh filesystem is running low on inodes";
                  description = "{{ $labels.instance }} {{ $labels.mountpoint }} has less than 10% free inodes for 15 minutes. File creation can fail even when disk space remains.";
                })
                (alert {
                  name = "HostBackupFailed";
                  expr = ''sinnoh_backup_last_run_success{job="node"} == 0'';
                  duration = "5m";
                  severity = "warning";
                  summary = "A host backup failed";
                  description = "The latest {{ $labels.backup }} backup on {{ $labels.instance }} failed. Check restic-backups-{{ $labels.backup }}.service and retry after correcting the failure.";
                })
                (alert {
                  name = "HostBackupOverdue";
                  expr = ''time() - (sinnoh_backup_last_success_timestamp_seconds{job="node"} > 0) > 48 * 60 * 60'';
                  duration = "15m";
                  severity = "critical";
                  summary = "A host backup is overdue";
                  description = "The {{ $labels.backup }} backup on {{ $labels.instance }} has not succeeded in over 48 hours. Check its timer and restic service.";
                })
                (alert {
                  name = "HostBackupSuccessMissing";
                  expr = ''
                    sinnoh_backup_job_info{job="node"}
                    unless on (instance, backup)
                    (sinnoh_backup_last_success_timestamp_seconds{job="node"} > 0)
                  '';
                  duration = "48h";
                  severity = "warning";
                  summary = "A host backup has no recorded success";
                  description = "The {{ $labels.backup }} backup on {{ $labels.instance }} has had no valid success timestamp for 48 hours. Check the backup and its metrics reporter.";
                })
                (alert {
                  name = "PostgresBackupFailed";
                  expr = ''${postgresBackupFailure} > on (namespace) ${postgresBackupSuccess}'';
                  duration = "5m";
                  severity = "warning";
                  labels.postgres_cluster = "pg-shared";
                  summary = "The PostgreSQL backup failed";
                  description = "The latest pg-shared backup failed after the last successful backup. Check the CloudNativePG Backup resource and Barman logs.";
                })
                (alert {
                  name = "PostgresBackupOverdue";
                  expr = ''time() - (${postgresBackupSuccess} > 0) > 48 * 60 * 60'';
                  duration = "15m";
                  severity = "critical";
                  labels.postgres_cluster = "pg-shared";
                  summary = "The PostgreSQL backup is overdue";
                  description = "pg-shared has no successful base backup from the last 48 hours. Check its daily ScheduledBackup and Barman object store.";
                })
                (alert {
                  name = "PostgresBackupSuccessMissing";
                  expr = ''${postgresBackupSuccess} == 0'';
                  duration = "48h";
                  severity = "warning";
                  labels.postgres_cluster = "pg-shared";
                  summary = "PostgreSQL has no recorded successful backup";
                  description = "pg-shared has reported no successful base backup for 48 hours. Check the ScheduledBackup and Barman object store.";
                })
                (alert {
                  name = "FluxReconciliationFailed";
                  expr = ''
                    max by (namespace, name, customresource_kind) (
                      gotk_resource_info{job="kube-state-metrics",ready!="True",suspended!="true",source_type!="oci"}
                    ) == 1
                  '';
                  duration = "15m";
                  severity = "warning";
                  summary = "A Flux resource is not ready";
                  description = "{{ $labels.customresource_kind }} {{ $labels.namespace }}/{{ $labels.name }} has stayed unready for 15 minutes. Check its conditions and Flux events.";
                })
                (alert {
                  name = "FluxTelemetryMissing";
                  expr = ''absent_over_time(gotk_resource_info{job="kube-state-metrics",customresource_kind="Kustomization"}[10m])'';
                  duration = "5m";
                  severity = "critical";
                  summary = "Flux resource status metrics have stopped";
                  description = "No Flux Kustomization metrics have arrived for ten minutes, and the absence has persisted for five more minutes. Check kube-state-metrics configuration, RBAC, and Alloy.";
                })
                (alert {
                  name = "KubernetesDeploymentUnavailable";
                  expr = ''
                    (max by (namespace, deployment) (kube_deployment_status_replicas_available{job="kube-state-metrics"}) == 0)
                    and on (namespace, deployment)
                    (max by (namespace, deployment) (kube_deployment_spec_replicas{job="kube-state-metrics"}) > 0)
                  '';
                  duration = "5m";
                  severity = "critical";
                  summary = "A Kubernetes deployment has no available replicas";
                  description = "The deployment requests at least one replica but has had none available for five minutes. Check scheduling, probes, and pod events.";
                })
                (alert {
                  name = "KubernetesDeploymentReplicasMissing";
                  expr = ''
                    max by (namespace, deployment) (kube_deployment_status_replicas_available{job="kube-state-metrics"})
                    < on (namespace, deployment)
                    max by (namespace, deployment) (kube_deployment_spec_replicas{job="kube-state-metrics"})
                  '';
                  duration = "15m";
                  severity = "warning";
                  summary = "A Kubernetes deployment is below its desired replica count";
                  description = "Available replicas have stayed below the desired count for 15 minutes. Check rollout progress and scheduling capacity.";
                })
                (alert {
                  name = "KubernetesContainerOOMKilled";
                  expr = ''
                    (max by (namespace, pod, container) (increase(kube_pod_container_status_restarts_total{job="kube-state-metrics"}[10m])) > 0)
                    and on (namespace, pod, container)
                    (max by (namespace, pod, container) (kube_pod_container_status_last_terminated_reason{job="kube-state-metrics",reason="OOMKilled"}) == 1)
                  '';
                  duration = "0m";
                  severity = "warning";
                  summary = "A Kubernetes container restarted after an OOM kill";
                  description = "A restart occurred in the last ten minutes and Kubernetes reports OOMKilled as the last termination reason. Review memory use and the container limit.";
                })
                (alert {
                  name = "KubernetesContainerRestarting";
                  expr = ''max by (namespace, pod, container) (increase(kube_pod_container_status_restarts_total{job="kube-state-metrics"}[15m])) >= 3'';
                  duration = "5m";
                  severity = "warning";
                  summary = "A Kubernetes container is restarting repeatedly";
                  description = "At least three restarts occurred in a rolling 15-minute window and the condition has persisted for five minutes. Check termination reasons and logs.";
                })
                (alert {
                  name = "KubernetesContainerMemoryNearLimit";
                  expr = ''
                    max by (namespace, pod, container) (container_memory_working_set_bytes{job="cadvisor",container!="",container!="POD",image!=""})
                    / on (namespace, pod, container)
                    (max by (namespace, pod, container) (kube_pod_container_resource_limits{job="kube-state-metrics",resource="memory"}) > 0)
                    > 0.90
                  '';
                  duration = "15m";
                  severity = "warning";
                  summary = "A Kubernetes container has little memory headroom";
                  description = "The working set has exceeded 90% of the memory limit for 15 minutes. Review recent memory growth before raising the limit.";
                })
                (alert {
                  name = "PublicServiceHTTPErrorRateHigh";
                  expr = ''
                    label_replace(
                      (
                        sum by (service) (rate(traefik_router_requests_total{job="traefik",service=~"(slingshot|skytrace)-.*@kubernetes",code=~"5.."}[5m]))
                        / sum by (service) (rate(${serviceRequests}[5m]))
                        > 0.05
                      ) and on (service) (${serviceTraffic}),
                      "namespace", "$1", "service", "(slingshot|skytrace)-.*"
                    )
                  '';
                  duration = "10m";
                  severity = "critical";
                  summary = "A public service has a sustained HTTP 5xx error rate";
                  description = "More than 5% of requests have returned HTTP 5xx for ten minutes, with at least 50 requests per five-minute window. Router counters include gateway failures. HTTP 400 is not classified as a server failure.";
                })
                (alert {
                  name = "PublicServiceLatencyHigh";
                  expr = ''
                    label_replace(
                      (histogram_quantile(0.95, sum by (service, le) (rate(${serviceBuckets}[5m]))) > 1)
                      and on (service) (sum by (service) (increase(${serviceSuccesses}[5m])) >= 50),
                      "namespace", "$1", "service", "(slingshot|skytrace)-.*"
                    )
                  '';
                  duration = "10m";
                  severity = "warning";
                  summary = "A public service has sustained high backend latency";
                  description = "Successful-request p95 latency has exceeded one second for ten minutes, with at least 50 successful requests per five-minute window. This measures Traefik-to-service duration, excluding Cloudflare and client network time.";
                })
                (alert {
                  name = "MetricsScrapeFailed";
                  expr = ''up{job!="node"} == 0'';
                  duration = "5m";
                  severity = "warning";
                  summary = "A Prometheus scrape target is failing";
                  description = "The collector has failed to scrape this target for five minutes. Check the metrics endpoint and collector before relying on its dashboards.";
                })
              ]
              ++ map (job:
                alert {
                  name = "MetricsTelemetryMissing";
                  expr = ''absent_over_time(up{job="${job}"}[5m])'';
                  duration = "2m";
                  severity = "critical";
                  labels = {inherit job;};
                  summary = "A required metrics feed has stopped";
                  description = "No ${job} target samples have arrived for at least five minutes, and the absence has persisted for two more minutes. Check Alloy and Prometheus remote write.";
                }) ["cadvisor" "kube-state-metrics" "slingshot" "traefik"];
          }
        ];
      }))
    ];
  };
}
