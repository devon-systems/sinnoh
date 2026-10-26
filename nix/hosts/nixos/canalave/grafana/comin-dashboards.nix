_: {
  flake.nixosModules.canalave = {
    config,
    lib,
    pkgs,
    ...
  }: let
    provider = cluster: let
      helpers = import ./_lib.nix {
        inherit lib;
        datasources = config.services.grafana.provision.datasources.settings.datasources;
        interval = "1m";
      };
      inherit (helpers) target;
      variable = helpers.variable prometheus;
      prometheus = helpers.source "${cluster} Prometheus";
      loki = helpers.source "${cluster} Loki";
      selector = ''job="comin",host=~"$host"'';
      dashboard = helpers.dashboard prometheus {
        uid = "${lib.toLower cluster}-comin";
        title = "${cluster} Comin";
        description = "Comin deployment state and logs. Failure flags reset when Comin restarts. Missing telemetry is unknown; sleeping desktops leave gaps.";
        tags = [(lib.toLower cluster) "comin"];
        variables = [
          (variable "host" ''label_values(up{job="comin"}, host)'')
        ];
        panels = [
          {
            title = "Comin reachable";
            type = "stat";
            description = "Whether Alloy can scrape the local Comin exporter. This does not indicate deployment success.";
            targets = [(target ''up{${selector}}'' "{{host}}")];
            mappings = [
              {
                type = "value";
                options = {
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
            ];
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
            mappings = [
              {
                type = "value";
                options = {
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
            ];
          }
          {
            title = "Reboot required";
            type = "stat";
            description = "Comin's reboot-required flag for Linux hosts. macOS is excluded because it does not expose the same booted-system comparison.";
            targets = [(target ''comin_need_to_reboot{${selector},os!="darwin"}'' "{{host}}")];
            mappings = [
              {
                type = "value";
                options = {
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
            ];
          }
          {
            title = "Latest reported deployment";
            transformations = [
              {
                id = "filterFieldsByName";
                options.include.names = ["host" "commit_id" "status"];
              }
            ];
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
            gridPos.w = 24;
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
    services.grafana.provision.dashboards.settings.providers = map provider ["Hoenn" "Johto" "Sinnoh" "Kanto"];
  };
}
