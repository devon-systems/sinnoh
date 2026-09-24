{lib, ...}: {
  flake.nixosModules.sunnyshore = {
    services.coredns = {
      enable = true;
      config = lib.concatStringsSep "\n" [
        "sinnoh:53 {"
        "  bind 10.254.0.2 10.254.1.1"
        "  hosts {"
        "    10.254.0.2 sunnyshore.sinnoh"
        "    10.254.0.3 canalave.sinnoh"
        "  }"
        "}"
        ""
        "hoenn:53 {"
        "  bind 10.254.0.2 10.254.1.1"
        "  hosts {"
        "    10.254.1.6 fallarbor.hoenn"
        "    10.254.1.5 fortree.hoenn"
        "    10.254.1.9 lilycove.hoenn"
        "    10.254.1.2 mauville.hoenn"
        "    10.254.1.7 pacifidlog.hoenn"
        "    10.254.1.8 petalburg.hoenn"
        "    10.254.1.1 sunnyshore.hoenn"
        "    10.254.1.3 rustboro.hoenn"
        "    10.254.1.4 sootopolis.hoenn"
        "  }"
        "}"
      ];
    };

    systemd.services.coredns = {
      after = ["wireguard-hoenn.service" "wireguard-sinnoh.service"];
      requires = ["wireguard-hoenn.service" "wireguard-sinnoh.service"];
    };
  };
}
