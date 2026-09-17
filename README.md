# Mythic Scripts

[![GitHub stars](https://img.shields.io/github/stars/ice-wzl/mythic_scripts?style=flat-square)](https://github.com/ice-wzl/mythic_scripts/stargazers)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue.svg?style=flat-square)](LICENSE)
[![Mythic](https://img.shields.io/badge/Mythic-C2-6f42c1?style=flat-square)](https://github.com/its-a-feature/Mythic)

A practical collection of setup scripts, eventing workflows, post-exploitation automations, and operator helpers for [Mythic C2](https://github.com/its-a-feature/Mythic).

The goal is simple: turn common operator tasks into reusable, reviewable automation. The repository currently covers repeatable Mythic provisioning, automatic callback sleep configuration, Windows and Linux host surveys, Apollo post-exploitation workflows, and richer file-browser output.

> [!WARNING]
> This project is intended for authorized security testing, adversary simulation, and lab use only. Several workflows enumerate sensitive host data or credential material. Review every file before importing it and only run it on systems you own or have explicit permission to test.

## Highlights

- Bootstrap Docker and a vanilla Mythic deployment on Debian-family Linux hosts.
- Install a curated catalog of 21 Mythic agents, C2 profiles, extensions, integrations, and wrappers.
- Import ready-to-run Eventing workflows for Apollo, Poseidon, Merlin, and Poopsie.
- Run structured Windows and Linux discovery surveys with failure-tolerant steps.
- Automate Apollo privilege, defensive-control, user-data, and credential-access tasks.
- Improve Apollo `ls` output with file-type icons, metadata, ACL views, downloads, deletion controls, and directory highlighting.

## Repository layout

```text
mythic_scripts/
├── setup/                  # Docker, Mythic core, and component installers
├── eventing/
│   ├── auto_set_sleep/     # New-callback sleep policies
│   └── surveys/            # Apollo and Poseidon host surveys
├── post_ex/                # Apollo/Mimikatz Eventing workflows
├── scripts/apollo/         # PowerShell imported by an Apollo workflow
└── browser_scripts/        # Mythic browser-script customizations
```

## What's included

### Setup automation

| Script | Purpose |
| --- | --- |
| [`install-docker.sh`](setup/install-docker.sh) | Installs Docker Engine and Compose v2 from Docker's official apt repository. |
| [`mythic-install.sh`](setup/mythic-install.sh) | Clones, builds, and starts a vanilla Mythic core installation. |
| [`mythic-components.sh`](setup/mythic-components.sh) | Installs selected optional agents, profiles, and services—or the full catalog. |

The installers support Debian-family Linux systems, default to `/opt/mythic`, detect legacy `/opt/Mythic` installations, and expose environment overrides for custom paths or pinned Mythic refs. See the [setup guide](setup/README.md) for all options.

### Eventing workflows

| Workflow | Trigger | What it does |
| --- | --- | --- |
| `apollo_windows_base_survey.yaml` | Manual | Runs a 28-step non-administrator Windows survey covering identity, processes, networking, users, software, history, tasks, services, and common filesystem locations. |
| `poseidon_linux_base_survey.yaml` | Manual | Runs a 36-step non-root Linux survey covering host context, filesystems, processes, networking, recent changes, cron, and selected configuration files. |
| `apollo_antivirus_survey.yaml` | Manual | Surveys Microsoft Defender configuration and uses Forge modules to inspect defensive controls and EDR products. |
| `apollo_priv_checks.yaml` | Manual | Registers and runs SharpUp, Seatbelt, and Snaffler Forge modules for common privilege-escalation checks. |
| `apollo_user_enumeration.yaml` | Manual | Imports and runs `Invoke-UserEnum.ps1` to identify potentially useful files and browser artifacts under Windows profiles. |
| `*_4h_callbacks.yaml` | New callback | Sets new Apollo, Poseidon, Merlin, or Poopsie callbacks to a four-hour sleep interval. Apollo, Poseidon, and Poopsie use 20% jitter. |

### Post-exploitation workflows

| Workflow | Purpose |
| --- | --- |
| `mimikatz_base.yaml` | Chains common Apollo Mimikatz credential collection commands for logon sessions, LSA secrets, Credential Manager, and Windows Vault. |
| `mimikatz_dcsync.yaml` | Runs targeted DCSync requests for the `krbtgt` and `Administrator` accounts. |

These workflows require the appropriate privileges and Apollo commands. The DCSync workflow must run from a context authorized to replicate directory secrets.

### Operator helpers

- [`Invoke-UserEnum.ps1`](scripts/apollo/Invoke-UserEnum.ps1) safely walks selected profile locations, avoids reparse-point loops, checks targeted browser and credential artifacts, and marks potentially interesting files.
- [`apollo_ls.js`](browser_scripts/apollo_ls.js) provides a richer Apollo file-listing table with typed icons, timestamps, ownership, ACL and extended-attribute views, plus task buttons for browsing, reading, downloading, and deleting entries.

## Quick start

### Use the workflows with an existing Mythic server

1. Clone or download this repository.
2. In Mythic, open **Eventing** and import the YAML file you want from [`eventing/`](eventing) or [`post_ex/`](post_ex).
3. Review the trigger, commands, parameters, and `run_as` value before enabling or running it.
4. For a manual workflow, select the intended callback and launch it from Eventing.

The Apollo user-enumeration workflow has one additional step: after importing it, use the workflow's paperclip attachment control to upload [`Invoke-UserEnum.ps1`](scripts/apollo/Invoke-UserEnum.ps1). The workflow references that upload as `Invoke-UserEnum.ps1`.

> [!TIP]
> Import only the callback sleep policy for payload types you actually use. These policies execute automatically whenever a matching callback is created.

### Provision a new Mythic server

On a Debian-family Linux host:

```bash
git clone https://github.com/ice-wzl/mythic_scripts.git
cd mythic_scripts/setup
chmod +x install-docker.sh mythic-install.sh mythic-components.sh

sudo ./install-docker.sh
sudo ./mythic-install.sh
sudo ./mythic-components.sh apollo http basic_logger
```

To inspect the component catalog:

```bash
./mythic-components.sh --help
```

Installing every catalog component can require substantial disk space, memory, and download time:

```bash
sudo ./mythic-components.sh --all
```

See [`setup/README.md`](setup/README.md) for distro overrides, custom installation paths, updates, and version pinning.

## Requirements and compatibility

- A current Mythic installation with access to the Eventing interface.
- The payload type named by the imported workflow: Apollo, Poseidon, Merlin, or Poopsie.
- Workflow-specific commands installed in that payload type.
- Forge and the referenced `forge_net_*` modules for the Apollo antivirus and privilege-check workflows.
- Elevated privileges for credential-dumping tasks and any survey data the current callback cannot normally access.
- For provisioning: Debian-family Linux, root access, Docker Engine 20.10.22 or newer, and Docker Compose v2.

Mythic agents and commands evolve. If an import succeeds but a task does not, compare the workflow's `command_name` and parameters with the version of the payload type installed on your server.

## Customizing a workflow

Every Eventing file is plain YAML. A typical task step looks like this:

```yaml
- name: "current identity"
  depends_on: []
  inputs:
    CALLBACK_ID: env.display_id
  action: task_create
  continue_on_error: true
  action_data:
    callback_display_id: CALLBACK_ID
    command_name: whoami
```

Fork the repository and adapt sleep intervals, survey steps, command parameters, or dependencies to match your operation. Keep destructive or high-impact actions explicit and easy to review.

## Contributing

Issues and pull requests are welcome. Useful contributions include:

- workflows for additional Mythic agents;
- fixes for command changes in newer agent releases;
- safer or more focused survey variants;
- setup-script portability and validation improvements; and
- browser-script usability enhancements.

When submitting a workflow, document its required agent, privileges, external modules, trigger behavior, and any files that must be attached after import. Please do not include live infrastructure details, credentials, payloads, or data collected from engagements.

If this repository saves you time, consider [giving it a star](https://github.com/ice-wzl/mythic_scripts)—it helps other Mythic operators find it.

## License

Licensed under the [GNU General Public License v3.0](LICENSE).
