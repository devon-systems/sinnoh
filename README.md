# sinnoh

Declarative infrastructure for my production services. Sinnoh combines NixOS,
k3s, Flux, SOPS, and OpenTofu to manage hosts, applications, networking, DNS,
and backups.

For my personal homelab, see [johto](https://github.com/alyraffauf/johto).
For my personal Nix flake, see [hoenn](https://github.com/alyraffauf/hoenn).

## Architecture

| Host                                                 | Role                                     |
| ---------------------------------------------------- | ---------------------------------------- |
| [`sunnyshore`](nix/hosts/nixos/sunnyshore/README.md) | k3s server and control-plane data backup |
| [`canalave`](nix/hosts/nixos/canalave/README.md)     | k3s agent and observability services     |

Both hosts run NixOS on OpenStack and communicate over the `sinnoh` WireGuard
interface. Flux watches the `master` branch and reconciles the application,
networking, certificate, database, backup, and secret resources composed by
`k8s/flux-system/`.

## Repository layout

```text
nix/
├── hosts/nixos/       Per-host NixOS configuration and hardware state
└── nixos/             Shared modules, features, services, and users
k8s/                  Flux, Kustomize, Helm, and application manifests
secrets/              SOPS-encrypted host secrets
keys/                 Public SSH keys used to derive age recipients
terraform/            OpenTofu configuration for Cloudflare DNS
scripts/              Repository maintenance utilities
```

`flake.nix` imports the flake-parts modules under `nix/` and exposes the
`sunnyshore` and `canalave` NixOS configurations. Kubernetes applications are
grouped by service under `k8s/`. `k8s/flux-system/` defines their reconciliation
order.

## Work locally

Enter the pinned development shell with `nix develop`, or use `direnv allow`
to load it automatically. From the repository root:

```sh
nix fmt
nix flake check
```

Run `just` to list maintenance commands.

## Deployment

`blzrd` deploys `sunnyshore` and `canalave`. For example:

```sh
blzrd switch sunnyshore
```

`switch` activates the configuration and sets the boot default. `boot` sets
the boot default without activating it. Without a host name, `blzrd switch`
deploys every registered node.

Flux deploys Kubernetes workloads from `master`. OpenTofu manages DNS.

## Secrets

SOPS encrypts secrets for the recipients in `.sops.yaml`. Public keys live in
`keys/`. To edit a host secret from the development shell:

```sh
just sops-edit tailscale.yaml
```

Direnv loads the encrypted Cloudflare and Backblaze credentials for OpenTofu.

This project is available under the [MIT License](LICENSE.md).
