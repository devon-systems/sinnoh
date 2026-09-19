{self, ...}: {
  perSystem = {pkgs, ...}: {
    checks.monitoring-queries = pkgs.runCommand "monitoring-query-tests" {nativeBuildInputs = [pkgs.prometheus.cli];} ''
      cp ${pkgs.writeText "workload-rules.json" (builtins.head self.nixosConfigurations.canalave.config.services.prometheus.rules)} workload-rules.json
      cp ${../tests/workload-rules.yaml} tests.yaml
      promtool check rules workload-rules.json
      promtool test rules tests.yaml
      touch "$out"
    '';
  };
}
