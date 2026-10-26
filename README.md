# sinnoh

NixOS, k3s, and OpenTofu configuration for production services. Sinnoh manages
hosts, applications, private networking, Cloudflare DNS, and backups.

See also [Hoenn](https://github.com/devon-systems/hoenn) for personal machines,
[Johto](https://github.com/devon-systems/johto) for the homelab, and
[Kanto](https://github.com/devon-systems/kanto) for shared inference.

## Architecture

| Host                                                 | Role                                     |
| ---------------------------------------------------- | ---------------------------------------- |
| [`sunnyshore`](nix/hosts/nixos/sunnyshore/README.md) | k3s server and control-plane data backup |
| [`canalave`](nix/hosts/nixos/canalave/README.md)     | k3s agent and observability services     |

Both hosts run NixOS on OpenStack and communicate over the `sinnoh` WireGuard
interface.

Comin reconciles host configurations from `master`. Flux reconciles the
Kubernetes resources in `k8s/flux-system/` from the same branch. OpenTofu
manages Cloudflare DNS separately.

## Repository layout

```text
nix/
├── hosts/nixos/       Host configuration and hardware state
└── nixos/             Shared modules, services, and users
k8s/                  Flux and application manifests
secrets/              SOPS-encrypted host secrets
keys/                 Public SOPS recipients
terraform/            OpenTofu configuration for Cloudflare DNS
scripts/              Maintenance tools
```

`flake.nix` imports the flake-parts modules under `nix/` and exposes the
`sunnyshore` and `canalave` NixOS configurations. Kubernetes secrets live in
`k8s/secrets/`.

## Development

Enter the pinned development shell with `nix develop`, or run `direnv allow` to
load it automatically. Then run:

```sh
nix fmt
nix flake check
```

Build each host affected by a Nix change. Build both hosts after changing a
shared NixOS module:

```sh
nix build .#nixosConfigurations.sunnyshore.config.system.build.toplevel
nix build .#nixosConfigurations.canalave.config.system.build.toplevel
```

After Kubernetes changes, run `just check-k8s`. For OpenTofu changes, run
`tofu -chdir=terraform init` on a fresh checkout, then run:

```sh
tofu -chdir=terraform fmt -check
tofu -chdir=terraform plan
```

Run `just` to list the other maintenance commands.

## Deployment

Commit and push validated changes, then let Comin and Flux reconcile `master`.
Run `just flux-status` to inspect the cluster through the `sinnoh` context.

Review the OpenTofu plan before applying DNS changes. The B2 state backend does
not lock state, so never run concurrent applies.

The [observability runbook](https://github.com/devon-systems/infra/blob/master/docs/observability.md)
explains how to check metrics and logs.

## Secrets

Run `just sops-bootstrap` once per machine to derive your local age key from
your SSH key. Then edit secrets with SOPS:

```sh
just sops-edit tailscale.yaml
just sops-edit k8s/secrets/pg-shared-b2.sops.yaml
```

Direnv loads the encrypted Cloudflare and Backblaze credentials for OpenTofu.
After changing `keys/`, run `just sops-rekey`. Commit `.sops.yaml` and all
re-encrypted files together. Never commit decrypted secrets, private keys,
OpenTofu state, or saved plans.

Licensed under the [MIT License](LICENSE.md).
