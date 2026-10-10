_: {
  flake.nixosModules.canalave = {
    config,
    lib,
    pkgs,
    ...
  }: let
    prometheus = lib.findFirst (source: source.name == "Sinnoh Prometheus") null config.services.grafana.provision.datasources.settings.datasources;
    datasource = {
      type = "prometheus";
      inherit (prometheus) uid;
    };
    requests = ''server_request_count{job="slingshot",endpoint!="GET /"}'';
    requestRate = "sum(rate(${requests}[$__rate_interval]))";
    errorRate = ''sum(rate(server_request_count{job="slingshot",endpoint!="GET /",status=~"5.. .*"}[$__rate_interval]))'';
    fetchRate = lib.concatStringsSep " + " (map
      (kind: ''(sum(rate(slingshot_fetch_${kind}_count{job="slingshot"}[$__rate_interval])) or vector(0))'')
      ["record" "handle" "did_doc"]);
    latencyBuckets = ''traefik_service_request_duration_seconds_bucket{job="traefik",service="slingshot-slingshot-http@kubernetes",code="200"}'';
    fetchMean = kind: ''sum(rate(slingshot_fetch_${kind}_sum{job="slingshot",success="true"}[$__rate_interval])) / sum(rate(slingshot_fetch_${kind}_count{job="slingshot",success="true"}[$__rate_interval]))'';
    resources = ''job="kube-state-metrics",namespace="slingshot",container="slingshot"'';
    containers = ''job="cadvisor",namespace="slingshot",container="slingshot",image!=""'';

    target = expr: legendFormat: {
      inherit expr legendFormat;
    };

    panel = {
      id,
      title,
      description,
      x,
      y,
      unit,
      targets,
      type ? "timeseries",
    }: {
      inherit id title description type datasource;
      gridPos = {
        inherit x y;
        w =
          if type == "stat"
          then 6
          else 12;
        h =
          if type == "stat"
          then 4
          else 8;
      };
      targets = lib.imap0 (index: query:
        query
        // {
          inherit datasource;
          refId = "query-${toString index}";
          editorMode = "code";
          range = type != "stat";
          instant = type == "stat";
        })
      targets;
      fieldConfig = {
        defaults = {
          inherit unit;
          min = 0;
          color.mode = "palette-classic";
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
          colorMode = "value";
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
      uid = "sinnoh-slingshot";
      links = [
        {
          type = "dashboards";
          tags = ["sinnoh"];
          asDropdown = false;
          includeVars = true;
          keepTime = true;
          title = "Sinnoh";
        }
      ];
      title = "Slingshot";
      description = "Application and ingress metrics collected every 30 seconds. Application request panels exclude root health probes. Latency percentiles use Traefik histograms; upstream fetch latency uses counter-based means. Refresh attempts do not measure queue depth.";
      tags = ["sinnoh" "slingshot"];
      schemaVersion = 39;
      version = 1;
      editable = false;
      timezone = "browser";
      refresh = "30s";
      time = {
        from = "now-6h";
        to = "now";
      };
      panels = map panel [
        {
          id = 1;
          title = "Metrics endpoint reachable";
          description = "1 means the latest scrape succeeded; 0 means it failed. No data means the collector has not reported a target.";
          type = "stat";
          x = 0;
          y = 0;
          unit = "bool";
          targets = [
            (target ''min(up{job="slingshot"})'' "Application")
            (target ''min(up{job="traefik"})'' "Ingress")
          ];
        }
        {
          id = 2;
          title = "API requests per second";
          description = "Completed requests, excluding GET / health probes.";
          type = "stat";
          x = 6;
          y = 0;
          unit = "reqps";
          targets = [(target requestRate "Requests")];
        }
        {
          id = 3;
          title = "API HTTP 5xx rate";
          description = "Share of completed API requests with an HTTP 5xx response. Slingshot also maps some backend failures to HTTP 400, so this does not capture every backend failure.";
          type = "stat";
          x = 12;
          y = 0;
          unit = "percentunit";
          targets = [(target "(${errorRate} or vector(0)) / (${requestRate})" "Server errors")];
        }
        {
          id = 4;
          title = "Upstream fetches per second";
          description = "Record, handle, and DID-document fetches on cache misses, including unsuccessful fetches.";
          type = "stat";
          x = 18;
          y = 0;
          unit = "ops";
          targets = [(target fetchRate "Fetches")];
        }
        {
          id = 5;
          title = "API traffic by endpoint";
          description = "Completed requests per second, excluding root health probes.";
          x = 0;
          y = 4;
          unit = "reqps";
          targets = [(target "sum by (endpoint) (rate(${requests}[$__rate_interval]))" "{{endpoint}}")];
        }
        {
          id = 6;
          title = "HTTP response status";
          description = "Response rates by HTTP status. HTTP 400 includes invalid input and some backend failures; status alone cannot distinguish them.";
          x = 12;
          y = 4;
          unit = "reqps";
          targets = [(target "sum by (status) (rate(${requests}[$__rate_interval]))" "{{status}}")];
        }
        {
          id = 7;
          title = "Successful ingress service latency";
          description = "Estimated p50, p95, and p99 from Traefik service histograms over the selected rate interval. Includes requests routed to Slingshot with HTTP 200, including public root requests; excludes direct Kubernetes probes. Measures proxy-to-service duration, without Cloudflare or client network time. Histograms do not separate API endpoints.";
          x = 0;
          y = 12;
          unit = "s";
          targets = [
            (target "histogram_quantile(0.5, sum by (le) (rate(${latencyBuckets}[$__rate_interval])))" "p50")
            (target "histogram_quantile(0.95, sum by (le) (rate(${latencyBuckets}[$__rate_interval])))" "p95")
            (target "histogram_quantile(0.99, sum by (le) (rate(${latencyBuckets}[$__rate_interval])))" "p99")
          ];
        }
        {
          id = 8;
          title = "Upstream fetch outcomes";
          description = "External fetch rates by operation and success. These are cache-miss fetches, not total lookup counts.";
          x = 12;
          y = 12;
          unit = "ops";
          targets = [
            (target ''sum by (success) (rate(slingshot_fetch_record_count{job="slingshot"}[$__rate_interval]))'' "Records · success={{success}}")
            (target ''sum by (success) (rate(slingshot_fetch_handle_count{job="slingshot"}[$__rate_interval]))'' "Handles · success={{success}}")
            (target ''sum by (success) (rate(slingshot_fetch_did_doc_count{job="slingshot"}[$__rate_interval]))'' "DID documents · success={{success}}")
          ];
        }
        {
          id = 9;
          title = "Lookup volume";
          description = "Lookups including cache hits. Identity lookups can be internal work performed for a record request, so these counts are not HTTP request counts.";
          x = 0;
          y = 20;
          unit = "ops";
          targets = [
            (target ''sum(rate(slingshot_get_record{job="slingshot"}[$__rate_interval]))'' "Records")
            (target ''sum(rate(slingshot_get_handle{job="slingshot"}[$__rate_interval]))'' "Handles")
            (target ''sum(rate(slingshot_get_did_doc{job="slingshot"}[$__rate_interval]))'' "DID documents")
          ];
        }
        {
          id = 10;
          title = "Successful upstream fetch mean latency";
          description = "Request-weighted mean duration from sum/count counter rates. The deployed application summary percentiles are unreliable. No successful fetches produce no usable mean.";
          x = 12;
          y = 20;
          unit = "s";
          targets = [
            (target (fetchMean "record") "Records")
            (target (fetchMean "handle") "Handles")
            (target (fetchMean "did_doc") "DID documents")
          ];
        }
        {
          id = 11;
          title = "Jetstream event throughput";
          description = "Events received from Jetstream and handed to Slingshot. This does not measure how far the stream is behind real time.";
          x = 0;
          y = 28;
          unit = "ops";
          targets = [
            (target ''sum(rate(jetstream_total_events_received{job="slingshot"}[$__rate_interval]))'' "Received")
            (target ''sum(rate(jetstream_total_events_sent{job="slingshot"}[$__rate_interval]))'' "Delivered to Slingshot")
          ];
        }
        {
          id = 12;
          title = "Jetstream connections and errors";
          description = "Per-second rates of connection attempts, disconnects, and event errors. Event-driven counters appear after their first event.";
          x = 12;
          y = 28;
          unit = "ops";
          targets = [
            (target ''sum by (retry) (rate(jetstream_connects{job="slingshot"}[$__rate_interval]))'' "Connect · retry={{retry}}")
            (target ''sum by (reason) (rate(jetstream_disconnects{job="slingshot"}[$__rate_interval]))'' "Disconnect · {{reason}}")
            (target ''sum by (reason) (rate(jetstream_total_event_errors{job="slingshot"}[$__rate_interval]))'' "Event error · {{reason}}")
          ];
        }
        {
          id = 13;
          title = "Jetstream payload throughput";
          description = "Received payload bytes as counted by the exporter, grouped by transport compression. Excludes WebSocket overhead.";
          x = 0;
          y = 36;
          unit = "Bps";
          targets = [(target ''sum by (compressed) (rate(jetstream_total_bytes_received{job="slingshot"}[$__rate_interval]))'' "Compressed={{compressed}}")];
        }
        {
          id = 14;
          title = "Identity refresh outcomes";
          description = "Background refresh attempt rates. Failed DID attempts can repeatedly process a stuck queue head, so these are not completed-job counts. The exporter does not expose queue depth.";
          x = 12;
          y = 36;
          unit = "ops";
          targets = [
            (target ''sum by (success, reason) (rate(identity_handle_refresh{job="slingshot"}[$__rate_interval]))'' "Handles · success={{success}} · {{reason}}")
            (target ''sum by (success, reason) (rate(identity_did_refresh{job="slingshot"}[$__rate_interval]))'' "DID documents · success={{success}} · {{reason}}")
          ];
        }
        {
          id = 15;
          title = "Identity refresh scheduling attempts";
          description = "Attempts to schedule a refresh, counted before queue deduplication. Repeated attempts for the same identity are included. Do not subtract outcomes from these rates to infer queue depth.";
          x = 0;
          y = 44;
          unit = "ops";
          targets = [
            (target ''sum by (reason) (rate(identity_handle_refresh_queued{job="slingshot"}[$__rate_interval]))'' "Handles · {{reason}}")
            (target ''sum by (reason) (rate(identity_did_refresh_queued{job="slingshot"}[$__rate_interval]))'' "DID documents · {{reason}}")
          ];
        }
        {
          id = 16;
          title = "Ingress HTTP failures";
          description = "HTTP 4xx/5xx responses from Traefik for Slingshot, including gateway failures that never reach the application counters.";
          x = 12;
          y = 44;
          unit = "reqps";
          targets = [(target ''sum by (code) (rate(traefik_router_requests_total{job="traefik",router=~"(web-|websecure-)?slingshot-slingshot-slingshot-aly-town@kubernetes",code=~"[45].."}[$__rate_interval]))'' "HTTP {{code}}")];
        }
        {
          id = 17;
          title = "Slingshot memory and allocation";
          description = "Container working set and RSS alongside the Kubernetes memory request and limit. A larger limit adds headroom but does not fix unbounded application queues.";
          x = 0;
          y = 52;
          unit = "bytes";
          targets = [
            (target ''max by (pod) (container_memory_working_set_bytes{${containers}})'' "Working set · {{pod}}")
            (target ''max by (pod) (container_memory_rss{${containers}})'' "RSS · {{pod}}")
            (target ''max by (pod) (kube_pod_container_resource_requests{${resources},resource="memory"})'' "Request · {{pod}}")
            (target ''max by (pod) (kube_pod_container_resource_limits{${resources},resource="memory"})'' "Limit · {{pod}}")
          ];
        }
        {
          id = 18;
          title = "Slingshot CPU and allocation";
          description = "CPU usage in cores alongside the Kubernetes CPU request and limit.";
          x = 12;
          y = 52;
          unit = "cores";
          targets = [
            (target ''sum by (pod) (rate(container_cpu_usage_seconds_total{${containers}}[$__rate_interval]))'' "Usage · {{pod}}")
            (target ''max by (pod) (kube_pod_container_resource_requests{${resources},resource="cpu"})'' "Request · {{pod}}")
            (target ''max by (pod) (kube_pod_container_resource_limits{${resources},resource="cpu"})'' "Limit · {{pod}}")
          ];
        }
        {
          id = 19;
          title = "Container restarts in the last hour";
          description = "Kubernetes restart counter increases per pod over a rolling hour. Pod replacement starts a new counter; deleted pods disappear from current views.";
          x = 0;
          y = 60;
          unit = "short";
          targets = [(target ''sum by (pod) (increase(kube_pod_container_status_restarts_total{${resources}}[1h]))'' "{{pod}}")];
        }
        {
          id = 20;
          title = "Last container termination reason";
          description = "A value of 1 marks the last termination reason reported by Kubernetes. This persists until a later termination or pod replacement; it is not a count of new failures. Missing data means no recorded termination.";
          x = 12;
          y = 60;
          unit = "bool";
          targets = [(target ''max by (pod, reason) (kube_pod_container_status_last_terminated_reason{${resources}}) == 1'' "{{pod}} · {{reason}}")];
        }
      ];
    };
  in {
    services.grafana.provision.dashboards.settings.providers = [
      {
        name = "sinnoh-slingshot";
        folder = "Sinnoh";
        options.path = pkgs.writeTextDir "slingshot.json" (builtins.toJSON dashboard);
      }
    ];
  };
}
