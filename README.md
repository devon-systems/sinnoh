# 💎 sinnoh

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

## Repository Layout

```text
nix/
├── hosts/nixos/       Per-host NixOS configuration and hardware state
└── nixos/             Shared modules, features, services, and users
k8s/                  Flux, Kustomize, Helm, and application manifests
secrets/              SOPS-encrypted host and Kubernetes secrets
keys/                 Public SSH keys used to derive age recipients
terraform/            OpenTofu configuration for Cloudflare DNS
scripts/              Repository maintenance utilities
```

`flake.nix` imports the flake-parts modules under `nix/` and exposes the
`sunnyshore` and `canalave` NixOS configurations. Kubernetes applications are
grouped by service under `k8s/`; `k8s/flux-system/` defines their reconciliation
order.

## Development

Enter the pinned toolchain with `nix develop`, or run `direnv allow` to load it
automatically. The shell includes Bun, Just, OpenTofu, SOPS, `ssh-to-age`, and
`blzrd`. Useful commands from the repository root include:

```bash
# Format Nix, YAML, Markdown, TypeScript, and shell files.
nix fmt

# Evaluate the flake and run its configured checks.
nix flake check

# Build host configurations without activating them.
nix build .#nixosConfigurations.sunnyshore.config.system.build.toplevel
nix build .#nixosConfigurations.canalave.config.system.build.toplevel

# Refresh the generated host hardware documentation.
nix run github:alyraffauf/infra#generate-host-readmes

# Discover repository maintenance recipes.
just
```

CI evaluates the flake, builds the development shell, and builds both NixOS
hosts. Kubernetes changes are deployed through Flux after they reach `master`;
avoid applying repository manifests manually unless recovering the cluster.

## NixOS Deployments

`nix/deployments.nix` registers both hosts with `blzrd`. From the development
shell, deploy only the intended host whenever possible:

```bash
blzrd switch sunnyshore   # Activate Sunnyshore and set its boot default
blzrd switch canalave     # Activate Canalave and set its boot default
blzrd boot sunnyshore     # Set Sunnyshore's boot default without activating it
blzrd switch              # Deploy both registered hosts
```

Run the checks and build the affected host first. Supplying no node names
targets every registered node, so reserve the bare command for coordinated
fleet deployments.

## Secrets and DNS

Secrets are encrypted with SOPS for the recipients declared in `.sops.yaml`.
Never commit decrypted values, private keys, OpenTofu state, or saved plans.

```bash
just sops-bootstrap                         # Install this machine's age key once
just sops-edit tailscale.yaml               # Edit an encrypted host secret
just sops-edit k8s/secrets/vaultwarden-env.sops.yaml
just sops-rekey                             # Update recipients after keys/ changes
```

Direnv decrypts the Cloudflare and Backblaze credentials used by OpenTofu. The
configuration manages Cloudflare DNS and stores its remote state in Backblaze
B2. Review the plan before applying it:

```bash
tofu -chdir=terraform init
tofu -chdir=terraform plan
tofu -chdir=terraform apply
```

See [AGENTS.md](AGENTS.md) for contribution and validation guidelines. This
project is available under the [MIT License](LICENSE.md).
