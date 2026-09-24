{lib, ...}: let
  hoennNodes = {
    sunnyshore = {
      address = "10.254.1.1";
      publicKey = "vinYIK2laJ19yVMlw6iB5lb9+wY8ZBrM+Y4nrBmMxxQ=";
    };

    mauville = {
      address = "10.254.1.2";
      publicKey = "DLphP2R9EJ2TbIgaabt5ExQ461TdYX2EjlMsphxkVj8=";
    };

    rustboro = {
      address = "10.254.1.3";
      publicKey = "ZhpSQzxRmKrp3Tsny9rGP1PCtcP/zghdRoQJBPWPGGQ=";
    };

    sootopolis = {
      address = "10.254.1.4";
      publicKey = "ezW8vZQUpvcb2ltr8BOIn+iZ/lXI0mvNLs49ZiaZnCA=";
    };

    fortree = {
      address = "10.254.1.5";
      publicKey = "rquW00TzyERo86qdjA+Xc4dtFfNQIidxxIkp9Y6hSBY=";
    };

    fallarbor = {
      address = "10.254.1.6";
      publicKey = "ZbPq07drguGi6udpyBj1zOsyoxQzcm4awstyWIJRzAQ=";
    };

    pacifidlog = {
      address = "10.254.1.7";
      publicKey = "E8FXq8GhLhP83beFTzyN5G37rW5DgM9YcwtnQmaKQHs=";
    };

    petalburg = {
      address = "10.254.1.8";
      publicKey = "sodFLJVrTVsifP5ltziHkQrWDwEj+3Cvj6csZbWtgEE=";
    };

    lilycove = {
      address = "10.254.1.9";
      publicKey = "0FG8r6ua2z+o3etlbtmqql8dOu9T48Bx/PzBmSgv+kA=";
    };
  };
  hoennClients = lib.removeAttrs hoennNodes ["sunnyshore"];

  makePeer = _: node: {
    allowedIPs = ["${node.address}/32"];
    inherit (node) publicKey;
  };
in {
  flake.nixosModules.sunnyshore = {
    config,
    self,
    ...
  }: {
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

    sops.secrets.wireguard-hoenn-private = {
      sopsFile = self + "/secrets/wireguard-hoenn.yaml";
      key = "sunnyshore";
      mode = "0400";
    };

    networking = {
      firewall = {
        allowedUDPPorts = [51821];
        trustedInterfaces = lib.mkBefore ["hoenn"];
      };

      wireguard.interfaces.hoenn = {
        ips = ["${hoennNodes.sunnyshore.address}/24"];
        listenPort = 51821;
        privateKeyFile = config.sops.secrets.wireguard-hoenn-private.path;
        peers = lib.mapAttrsToList makePeer hoennClients;
      };
    };
  };
}
