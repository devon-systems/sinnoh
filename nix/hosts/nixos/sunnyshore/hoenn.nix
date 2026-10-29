{
  inputs,
  lib,
  ...
}: {
  flake.nixosModules.sunnyshore = {
    config,
    self,
    ...
  }: {
    imports = [inputs.wg-hoenn.nixosModules.hub];
    sops.secrets.wireguard-hoenn-private = {
      sopsFile = self + "/secrets/wireguard-hoenn.yaml";
      key = "sunnyshore";
      mode = "0400";
      restartUnits = ["wireguard-hoenn.service"];
    };
    wg-hoenn.privateKeyFile = config.sops.secrets.wireguard-hoenn-private.path;
    networking.firewall = {
      allowedUDPPorts = [inputs.wg-hoenn.lib.network.listenPort];
      trustedInterfaces = lib.mkBefore ["hoenn"];
    };
  };
}
