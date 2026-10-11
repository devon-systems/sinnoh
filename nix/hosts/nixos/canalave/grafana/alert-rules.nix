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
