# Mythic setup scripts

These scripts keep host provisioning, the vanilla Mythic installation, and
optional Mythic services separate.

After copying or cloning them onto the Linux host, make the scripts executable:

```bash
chmod +x install-docker.sh mythic-install.sh mythic-components.sh
```

## 1. Install Docker (when needed)

```bash
sudo ./install-docker.sh
```

The Docker installer supports Debian, Ubuntu, and derivatives that expose their
upstream release through standard OS metadata. For unusual or rolling
derivatives, specify the upstream Docker repository explicitly:

```bash
DOCKER_BASE_DISTRO=debian \
DOCKER_BASE_CODENAME=trixie \
sudo -E ./install-docker.sh
```

Docker only tests the distributions listed in its support matrix. A derivative
can be compatible without being officially supported by Docker.

## 2. Install vanilla Mythic

```bash
sudo ./mythic-install.sh
```

This installs and starts Mythic core only. It does not install an agent or C2
profile. Re-running it uses the existing checkout without updating it. To
fast-forward a clean existing checkout and rebuild `mythic-cli`:

```bash
sudo ./mythic-install.sh --update
```

To pin a new installation to a branch or tag:

```bash
MYTHIC_REF=v3.3.0 sudo -E ./mythic-install.sh
```

## 3. Install optional components

List the catalog and examples:

```bash
./mythic-components.sh --help
```

Install only the services required for the environment:

```bash
sudo ./mythic-components.sh apollo http basic_logger
```

Install every component in the catalog:

```bash
sudo ./mythic-components.sh --all
```

The all-components installation is intentionally separate from the vanilla
Mythic installer and can consume significant download time, disk space, and
memory because each component runs in its own container. If a third-party
component fails to install, the script continues through the rest of the
catalog, reloads Mythic, prints a failure summary, and exits with a nonzero
status.

All Mythic scripts accept `MYTHIC_DIR` to override the default `/opt/mythic`
path. Existing installations at the legacy `/opt/Mythic` path are detected
automatically.
