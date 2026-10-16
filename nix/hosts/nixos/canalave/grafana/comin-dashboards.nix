_: {
  flake.nixosModules.canalave = {
    config,
    lib,
    pkgs,
    ...
  }: let
    provider = cluster: let
      source = kind: let
        datasource = lib.findFirst (item: item.name == "${cluster} ${kind}") null config.services.grafana.provision.datasources.settings.datasources;
      in {inherit (datasource) type uid;};
      prometheus = source "Prometheus";
      loki = source "Loki";
      selector = ''job="comin",host=~"$host"'';
      target = expr: legendFormat: {inherit expr legendFormat;};
      panel = index: specification: let
        type = specification.type or "timeseries";
        datasource = specification.datasource or prometheus;
        instant = type == "stat" || type == "table";
      in {
        id = index + 1;
        inherit type datasource;
        inherit (specification) title description;
        gridPos = {
          x = lib.mod index 2 * 12;
          y = builtins.div index 2 * 8;
          w =
            if type == "logs"
            then 24
            else 12;
          h = 8;
        };
        targets = lib.imap0 (queryIndex: query:
          query
          // {
            refId = "query-${toString queryIndex}";
            inherit datasource instant;
            range = !instant;
            queryType =
              if instant
              then "instant"
              else "range";
            format =
              if type == "table"
              then "table"
              else "time_series";
          })
        specification.targets;
        transformations = lib.optional (type == "table") {
          id = "filterFieldsByName";
          options.include.names = ["host" "commit_id" "status"];
        };
        fieldConfig.defaults = {
          unit = specification.unit or "short";
          noValue = "Unknown";
          custom.spanNulls = false;
          mappings = lib.optional (specification ? states) {
            type = "value";
            options = specification.states;
          };
        };
        options =
          if type == "logs"
          then {
            showTime = true;
            showLabels = true;
            sortOrder = "Descending";
          }
          else if type == "stat"
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
        uid = "${lib.toLower cluster}-comin";
        title = "${cluster} Comin";
        description = "Comin deployment state and logs. Failure flags reset when Comin restarts. Missing telemetry is unknown; sleeping desktops leave gaps.";
        tags = [(lib.toLower cluster) "comin"];
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
            query = ''label_values(up{job="comin"}, host)'';
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
            title = "Comin reachable";
            type = "stat";
            description = "Whether Alloy can scrape the local Comin exporter. This does not indicate deployment success.";
            targets = [(target ''up{${selector}}'' "{{host}}")];
            states = {
              "0" = {
                text = "Unreachable";
                color = "red";
              };
              "1" = {
                text = "Reachable";
                color = "green";
              };
            };
          }
          {
            title = "Last operation failed";
            description = "1 means the latest operation failed. Flags start at 0, so zero alone does not prove the operation has run. Inspect deployment state and logs for context.";
            targets = map (operation: target "comin_last_${operation}_failed{${selector}}" "{{host}} ${operation} {{remote_name}}") ["fetch" "eval" "build" "deployment"];
          }
          {
            title = "Deployment suspended";
            type = "stat";
            description = "Whether Comin has suspended deployments on this host.";
            targets = [(target ''comin_is_suspended{${selector}}'' "{{host}}")];
            states = {
              "0" = {
                text = "Not suspended";
                color = "green";
              };
              "1" = {
                text = "Suspended";
                color = "orange";
              };
            };
          }
          {
            title = "Reboot required";
            type = "stat";
            description = "Comin's reboot-required flag for Linux hosts. macOS is excluded because it does not expose the same booted-system comparison.";
            targets = [(target ''comin_need_to_reboot{${selector},os!="darwin"}'' "{{host}}")];
            states = {
              "0" = {
                text = "No reboot reported";
                color = "green";
              };
              "1" = {
                text = "Reboot required";
                color = "orange";
              };
            };
          }
          {
            title = "Latest reported deployment";
            type = "table";
            description = "Commit and outcome of Comin's latest reported deployment. A failed row is an attempted deployment, not the active system revision.";
            targets = [(target ''comin_deployment_info{${selector}} == 1'' "{{host}}")];
          }
          {
            title = "Repository fetches per second";
            unit = "ops";
            description = "Fetch activity by repository and result. Counter resets are handled by rate().";
            targets = [(target ''rate(comin_fetch_count{${selector}}[$__rate_interval])'' "{{host}} {{remote_name}} {{status}}")];
          }
          {
            title = "Comin logs";
            type = "logs";
            datasource = loki;
            description = "Linux comin.service journals and macOS Comin file logs. Service labels apply to logs collected after this configuration is deployed.";
            targets = [(target ''{host=~"$host",service="comin"}'' "")];
          }
        ];
      };
    in {
      name = "${lib.toLower cluster}-comin";
      folder = cluster;
      options.path = pkgs.linkFarm "${dashboard.uid}-dashboard" [
        {
          name = "${dashboard.uid}.json";
          path = pkgs.writeText "${dashboard.uid}.json" (builtins.toJSON dashboard);
        }
      ];
    };
  in {
    services.grafana.provision.dashboards.settings.providers = map provider ["Hoenn" "Johto" "Sinnoh"];
  };
}
