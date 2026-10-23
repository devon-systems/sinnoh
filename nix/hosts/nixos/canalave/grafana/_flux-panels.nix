{target}: [
  {
    title = "Flux readiness";
    type = "table";
    transformations = [
      {
        id = "filterFieldsByName";
        options.include.names = ["customresource_kind" "exported_namespace" "name" "ready"];
      }
    ];
    unit = "short";
    targets = [(target ''gotk_resource_info{job="kube-state-metrics",exported_namespace=~"$namespace"}'' "{{customresource_kind}} {{name}} {{controller}}")];
    description = "Flux panels follow namespace only. Readiness and suspension come from resource state; missing state remains Unknown.";
  }

  {
    title = "Flux suspension";
    type = "table";
    transformations = [
      {
        id = "filterFieldsByName";
        options.include.names = ["customresource_kind" "exported_namespace" "name" "suspended"];
      }
    ];
    unit = "short";
    targets = [(target ''label_replace(gotk_resource_info{job="kube-state-metrics",exported_namespace=~"$namespace",suspended=""}, "suspended", "false", "suspended", ".*") or gotk_resource_info{job="kube-state-metrics",exported_namespace=~"$namespace",suspended!=""}'' "{{customresource_kind}} {{name}} {{controller}}")];
    description = "Flux panels follow namespace only. Readiness and suspension come from resource state; missing state remains Unknown.";
  }

  {
    title = "Flux pending generations";
    type = "table";
    transformations = [
      {
        id = "filterFieldsByName";
        options.include.names = ["customresource_kind" "exported_namespace" "name" "Value"];
      }
    ];
    unit = "short";
    targets = [(target ''clamp_min(gotk_resource_generation{job="kube-state-metrics",exported_namespace=~"$namespace"} - gotk_resource_observed_generation{job="kube-state-metrics",exported_namespace=~"$namespace"}, 0)'' "{{customresource_kind}} {{name}} {{controller}}")];
    description = "Flux panels follow namespace only. Readiness and suspension come from resource state; missing state remains Unknown.";
  }

  {
    title = "Flux reconciliation failures";
    type = "timeseries";
    unit = "short";
    targets = [(target ''sum by (controller) (increase(controller_runtime_reconcile_total{job="flux",result="error"}[$__range]))'' "{{controller}}")];
    description = "Errors cover all namespaces and are grouped by controller.";
  }

  {
    title = "Flux reconciliation duration p95";
    type = "timeseries";
    unit = "s";
    targets = [(target ''histogram_quantile(0.95, sum by (le,kind,name,namespace) (rate(gotk_reconcile_duration_seconds_bucket{job="flux",namespace=~"$namespace"}[$__rate_interval])))'' "{{kind}} {{namespace}}/{{name}}")];
    description = "Reconciliation duration follows the namespace filter.";
  }
  {
    title = "Flux work queue depth";
    targets = [(target ''sum by (name) (workqueue_depth{job="flux"})'' "{{name}}")];
    description = "Controller queues cover the whole cluster.";
  }
]
