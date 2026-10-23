{
  lib,
  datasources,
  interval ? "30s",
}: let
  source = name: let
    datasource = lib.findFirst (item: item.name == name) null datasources;
  in
    if datasource == null
    then throw "Grafana data source not configured: ${name}"
    else {inherit (datasource) type uid;};
  target = expr: legendFormat: {inherit expr legendFormat;};
  panel = defaultDatasource: index: specification: let
    type = specification.type or "timeseries";
    datasource = specification.datasource or defaultDatasource;
    instant = type == "stat" || type == "table";
  in {
    id = specification.id or (index + 1);
    inherit type datasource;
    inherit interval;
    inherit (specification) title;
    transformations = specification.transformations or [];
    description = specification.description or "Missing telemetry is shown as Unknown.";
    gridPos =
      {
        x = lib.mod index 2 * 12;
        y = builtins.div index 2 * 8;
        w = 12;
        h = 8;
      }
      // (specification.gridPos or {});
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
        inherit instant;
        range = !instant;
        queryType =
          if instant
          then "instant"
          else "range";
      })
    (specification.targets or [(target specification.expr (specification.legend or "{{instance}}"))]);
    fieldConfig = {
      defaults =
        {
          unit = specification.unit or "short";
          min = 0;
          max =
            if (specification.unit or "") == "percentunit"
            then 1
            else null;
          noValue = "Unknown";
          color.mode =
            if specification ? thresholds
            then "thresholds"
            else "palette-classic";
          custom = {spanNulls = false;};
          mappings =
            (specification.mappings or [])
            ++ lib.optional ((specification.unit or "") == "bool" && !(specification ? mappings)) {
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
      overrides =
        lib.optional (type == "table") {
          matcher = {
            id = "byRegexp";
            options = "^(?!Value$).*";
          };
          properties = [
            {
              id = "unit";
              value = "none";
            }
            {
              id = "mappings";
              value = [];
            }
          ];
        }
        ++ lib.optional (type == "table" && (specification ? thresholds || specification ? mappings || (specification.unit or "") == "bool")) {
          matcher = {
            id = "byName";
            options = "Value";
          };
          properties = [
            {
              id = "custom.cellOptions";
              value.type = "color-text";
            }
          ];
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
  variable = datasource: name: query: {
    inherit name query;
    label = lib.toUpper (builtins.substring 0 1 name) + builtins.substring 1 (-1) name;
    type = "query";
    inherit datasource;
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
  dashboard = datasource: specification: {
    inherit (specification) uid title;
    description = specification.description or "";
    links = specification.links or [];
    tags = specification.tags or [];
    schemaVersion = 39;
    version = 1;
    editable = false;
    timezone = "browser";
    refresh = interval;
    time =
      specification.time or {
        from = "now-6h";
        to = "now";
      };
    templating.list = specification.variables or [];
    panels = lib.imap0 (panel datasource) specification.panels;
  };
in {
  inherit source target panel variable dashboard;
}
