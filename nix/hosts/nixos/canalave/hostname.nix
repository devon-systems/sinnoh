_: {
  flake.nixosModules.canalave = {
    networking = {
      hostName = "canalave";
      # Resolve locally so Canalave's own telemetry doesn't depend on Sunnyshore's DNS.
      hosts."10.254.0.3" = ["canalave.sinnoh"];
    };
  };
}
