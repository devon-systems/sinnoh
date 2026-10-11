{self, ...}: {
  perSystem = {pkgs, ...}: let
    prometheus = self.nixosConfigurations.canalave.config.services.prometheus;
    ruleFiles = prometheus.ruleFiles ++ map (pkgs.writeText "prometheus-rules.yaml") prometheus.rules;
  in {
    checks.monitoring-queries =
      pkgs.runCommand "monitoring-query-tests" {
        nativeBuildInputs = [pkgs.prometheus.cli (pkgs.python3.withPackages (python: [python.pyyaml]))];
      } ''
        python3 - <<'PY'
        from pathlib import Path
        import yaml

        groups = []
        for filename in ${builtins.toJSON (map toString ruleFiles)}:
            groups.extend(yaml.safe_load(Path(filename).read_text())["groups"])
        Path("workload-rules.json").write_text(yaml.safe_dump({"groups": groups}))
        PY
        cp ${../tests/workload-rules.yaml} tests.yaml
        cp ${../tests/alert-rules.yaml} alert-tests.yaml
        promtool check rules workload-rules.json
        promtool test rules tests.yaml alert-tests.yaml
        touch "$out"
      '';
  };
}
