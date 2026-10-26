_: {
  flake.nixosModules.wireguardSinnoh = {
    config,
    lib,
    pkgs,
    self,
    ...
  }: let
    nodes = {
      sunnyshore = {
        address = "10.254.0.2";
        endpoint = "40.160.83.152:51820";
        publicKey = "FZ5JsQUGwOh/2LC/xBOXZExVes2tt2FR79L66Bep618=";
      };

      canalave = {
        address = "10.254.0.3";
        endpoint = "40.160.83.153:51820";
        publicKey = "QKkVUBoCNxLj0skHDxupy9tzAbceU9cDci+FQWCvEzk=";
      };
    };

    hostName = config.networking.hostName;
    currentNode = nodes.${hostName};
    peerNodes = lib.filterAttrs (nodeName: _: nodeName != hostName) nodes;
    resolvectl = lib.getExe' pkgs.systemd "resolvectl";

    makePeer = _: node: {
      allowedIPs = ["${node.address}/32"];
      inherit (node) endpoint;
      persistentKeepalive = 25;
      inherit (node) publicKey;
    };
  in {
    sops.secrets.wireguard-sinnoh-private = {
      sopsFile = self + "/secrets/wireguard-sinnoh.yaml";
      key = hostName;
      mode = "0400";
      restartUnits = ["wireguard-sinnoh.service"];
    };

    networking = {
      firewall = {
        allowedUDPPorts = [51820];
        trustedInterfaces = lib.mkBefore ["sinnoh"];
      };

      wireguard.interfaces.sinnoh = {
        ips = ["${currentNode.address}/24"];
        listenPort = 51820;
        privateKeyFile = config.sops.secrets.wireguard-sinnoh-private.path;
        postSetup = ''
          ${resolvectl} dns sinnoh 10.254.0.2
          ${resolvectl} domain sinnoh ~sinnoh
          ${resolvectl} default-route sinnoh false
        '';

        peers = lib.mapAttrsToList makePeer peerNodes;
      };
    };

    services.resolved.enable = true;
    systemd.services.wireguard-sinnoh.after = ["systemd-resolved.service"];
  };
}
