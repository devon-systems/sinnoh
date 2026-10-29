{
  inputs,
  lib,
  ...
}: let
  network = inputs.wg-hoenn.lib.network;
  hoennHosts = lib.mapAttrsToList (name: node: "    ${node.address} ${name}.${network.domain}") network.nodes;
in {
  flake.nixosModules.sunnyshore = {
    services.coredns = {
      enable = true;
      config = lib.concatStringsSep "\n" ([
          "sinnoh:53 {"
          "  bind 10.254.0.2 ${network.nodes.${network.hub}.address}"
          "  hosts {"
          "    10.254.0.2 sunnyshore.sinnoh"
          "    10.254.0.3 canalave.sinnoh"
          "  }"
          "}"
          ""
          "${network.domain}:53 {"
          "  bind 10.254.0.2 ${network.nodes.${network.hub}.address}"
          "  hosts {"
        ]
        ++ hoennHosts
        ++ [
          "  }"
          "}"
        ]);
    };

    systemd.services.coredns = {
      after = ["wireguard-hoenn.service" "wireguard-sinnoh.service"];
      requires = ["wireguard-hoenn.service" "wireguard-sinnoh.service"];
    };
  };
}
