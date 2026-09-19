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
      title = "Slingshot";
      description = "Slingshot application metrics collected every 30 seconds. Request panels exclude root health probes. Exported latency percentiles cover a rolling hour; counters reset when the process restarts.";
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
          targets = [(target ''min(up{job="slingshot"})'' "Reachable")];
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
          title = "API server error rate";
          description = "Share of completed API requests with an HTTP 5xx response. Client errors are shown separately below.";
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
          description = "Response rates by HTTP status, including client errors and server errors.";
          x = 12;
          y = 4;
          unit = "reqps";
          targets = [(target "sum by (status) (rate(${requests}[$__rate_interval]))" "{{status}}")];
        }
        {
          id = 7;
          title = "Successful API request latency";
          description = "Exporter-provided p50, p90, and p99 in seconds over its rolling one-hour window. Each pod is shown separately because summary percentiles cannot be combined.";
          x = 0;
          y = 12;
          unit = "s";
          targets = [(target ''server_request{job="slingshot",endpoint!="GET /",status="200 OK",quantile=~"0.5|0.9|0.99"}'' "{{endpoint}} · q{{quantile}} · {{instance}}")];
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
          title = "Successful upstream fetch latency, p90";
          description = "Exporter-provided 90th percentile over its rolling one-hour window, shown separately for each pod.";
          x = 12;
          y = 20;
          unit = "s";
          targets = [
            (target ''slingshot_fetch_record{job="slingshot",success="true",quantile="0.9"}'' "Records · {{instance}}")
            (target ''slingshot_fetch_handle{job="slingshot",success="true",quantile="0.9"}'' "Handles · {{instance}}")
            (target ''slingshot_fetch_did_doc{job="slingshot",success="true",quantile="0.9"}'' "DID documents · {{instance}}")
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
          description = "Background refresh completion rates. The exporter does not expose current refresh queue depth.";
          x = 12;
          y = 36;
          unit = "ops";
          targets = [
            (target ''sum by (success) (rate(identity_handle_refresh{job="slingshot"}[$__rate_interval]))'' "Handles · success={{success}}")
            (target ''sum by (success) (rate(identity_did_refresh{job="slingshot"}[$__rate_interval]))'' "DID documents · success={{success}}")
          ];
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
