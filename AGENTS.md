# Work in Sinnoh

Sinnoh runs production infrastructure. NixOS hosts Sunnyshore and Canalave live in `nix/hosts/nixos/`. Flux workloads live in `k8s/`, and Cloudflare DNS lives in `terraform/`. Keep host secrets in `secrets/`, Kubernetes secrets in `k8s/secrets/`, and public SOPS recipients in `keys/`.

## Validate changes

Before committing, run `nix fmt` and `nix flake check`. Build each changed host. Build both after shared NixOS module changes:

```sh
nix build .#nixosConfigurations.sunnyshore.config.system.build.toplevel
nix build .#nixosConfigurations.canalave.config.system.build.toplevel
```

After `facter.json` changes, run `nix run github:devon-systems/dvnpkgs#generate-host-readmes`. Never edit text between generated-section markers.

For Kubernetes changes, update resource lists and Flux resources together. Never reformat `k8s/flux-system/gotk-components.yaml`. Run `just check-k8s` to render Flux targets and local Helm releases with their configured values. The check fetches schemas over the network and validates remote Helm declarations. It skips encrypted SOPS documents and generated CRDs, but fails on other missing schemas. It also renders the pinned Tailscale operator Deployment with public values to verify resource settings. Other remote charts remain unrendered.

For OpenTofu changes, load credentials with direnv and run `tofu -chdir=terraform init` on a fresh checkout. Then run:

```sh
tofu -chdir=terraform fmt -check
tofu -chdir=terraform plan
```

## Commit messages

Use scoped Conventional Commits with a program, module, or path as scope, such as `fix(postgresql): restore database connectivity`.

## Deploy deliberately

Comin reconciles hosts and Flux reconciles Kubernetes from `master`. Push validated changes, let automation reconcile, and verify with read-only checks.

Manual deployment, forced reconciliation, Nix store copies to hosts, and deployment-service restarts require an explicit user request. Never deploy to test. Apply manifests with `kubectl` only for requested bootstrap or recovery.

The B2 backend does not lock OpenTofu state. Review every plan before applying. Never run concurrent applies.

## Keep secrets out of Git

Never commit decrypted secrets, private keys, OpenTofu state, or saved plans. Run `just sops-bootstrap` once to derive the local age key from SSH. Edit host secrets with `just sops-edit tailscale.yaml` and Kubernetes secrets with their full path, such as `just sops-edit k8s/secrets/pg-shared-b2.sops.yaml`.

After `keys/` changes, run `just sops-rekey`. Commit `.sops.yaml` with every re-encrypted file.
