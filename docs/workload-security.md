# Workload security

Application pod templates disable service account tokens and service-link
environment variables. Containers prevent privilege escalation and drop
`NET_RAW` or all capabilities. Pod seccomp profiles use `RuntimeDefault`.
Infrastructure controllers retain the Kubernetes API access they require.

Nginx sites retain their image startup users, writable filesystems, and
ownership capabilities. Bobbin and Pacifico keep their non-root profiles.
Tranquil PDS runs as UID and GID `65532` with all capabilities dropped.
Slingshot uses that same UID and GID, drops all capabilities, and has a
read-only root filesystem. Its writable mounts are `/cache`, limited to
`3Gi`, and `/tmp`, limited to `64Mi`.

## Network policies

Policies beside each application's manifests select its pods by label.
The eight Nginx sites accept HTTP only from Traefik and have no outbound
access. The ATBBS telnet server accepts port `2323` from Traefik and can make
public web requests.

Bobbin, Slingshot, Morsels, Pacifico, and Tranquil PDS allow DNS and public
web requests. Bobbin can also reach Slingshot on port `8080`. Tranquil PDS
can reach its Valkey on port `6379`, the shared PostgreSQL cluster on port
`5432`, and public SMTP on port `2465`. Alloy can reach Slingshot metrics on
port `8765` and Tranquil PDS metrics on port `3000`. Vaultwarden retains its
existing ingress and outbound restrictions.

Public outbound rules exclude private, tailnet, link-local, reserved, and
cluster public ingress addresses. Standard NetworkPolicy cannot select
external services by hostname. An allowed public web port can reach any
public address outside those exclusions.

## Limits

Policies are additive. Another policy that selects the same pod can grant
additional access. K3s uses kube-router to enforce these rules over Flannel.
NetworkPolicy does not provide complete isolation from the pod's own node,
host-network workloads, or host services. Host firewall rules and container
permissions remain separate controls.
