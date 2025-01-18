# Manifests for Fedora Atomic Desktops variants

This is the configuration needed to create
[rpm-ostree](https://coreos.github.io/rpm-ostree/) based, desktop variants of
Fedora, also known as
[Fedora Atomic Desktops](https://fedoraproject.org/atomic-desktops/). See the
Atomic Desktops project for more information about all of the variants.

This repo is managed by the
[Fedora Atomic Desktops SIG](https://fedoraproject.org/wiki/SIGs/AtomicDesktops).

Reach out to the SIG if you are interested in creating and maintaining a new
Atomic variant.

## Repository content

Each variant is described in a YAML
[treefile](https://coreos.github.io/rpm-ostree/treefile/) which is then used by
rpm-ostree to compose an ostree commit or OCI image with the package requested.

In the Fedora infrastructure, composes are made via
[pungi](https://forge.fedoraproject.org/pungi/pungi) with the configuration from:

- for Rawhide and branched composes:
  [forge.fedoraproject.org/releng/pungi-fedora](https://forge.fedoraproject.org/releng/pungi-fedora)
- for stable releases:
  [forge.fedoraproject.org/infra/ansible](https://forge.fedoraproject.org/infra/ansible/src/branch/main/roles/bodhi2/backend/templates/pungi.rpm.conf.j2)

Starting with Fedora 45, installer ISOs are built using
[image-builder](https://fedoraproject.org/wiki/Changes/BuildAtomicDesktopsWithImageBuilder).

For Fedora 44 and earlier, installer ISOs are built using
[Lorax](https://github.com/weldr/lorax) and additional templates:
[pagure.io/fedora-lorax-templates](https://pagure.io/fedora-lorax-templates).

## Getting started

If you'd like to build an Atomic system image, you'll need to clone this repo and check out the
release branch you want to work with, then build, publish, and install the image.

Currently, the default image type in Fedora is "ostree", while container images are
still in development. You can build either type.

All commonly used commands are listed as recipes in the
[justfile](https://pagure.io/workstation-ostree-config/blob/main/f/justfile) (see
[Just](https://github.com/casey/just)).

## Clone this repo

```
# Clone the config
git clone https://pagure.io/workstation-ostree-config && cd workstation-ostree-config

# Check out a release branch (unless you want a rawhide image)
git checkout f45
```

## ostree image

### Build an ostree image

```
# Build the classic ostree commits (currently the default in Fedora)
just compose-legacy silverblue
```

### Publish an ostree image

Serve the ostree repo using an HTTP server. You can use any static
file server. For example using
<https://github.com/TheWaWaR/simple-http-server>:

```
simple-http-server --index --ip 192.168.122.1 --port 8000
```

### Install the ostree image

On an already installed Silverblue system:

```
# Pin the currently deployed (and probably working) version
sudo ostree admin pin 0

# Add an ostree remote
sudo ostree remote add testremote http://192.168.122.1:8000/repo --no-gpg-verify

# List refs from variant remote
sudo ostree remote refs testremote

# Switch to your variant
sudo rpm-ostree rebase testremote:fedora/rawhide/x86_64/silverblue

# Reboot and test!
```

## Container image

### Build a container image

```
# Build the new ostree native container (not default yet, still in development)
just compose-image silverblue
```

### Publish the container image

Serve the container image using a local insecure container image registry.

```
# Run a local container image registry
podman run -d -p 5000:5000 --name local-registry registry:2

# Push the ociarchive to the image registry
REGISTRY=192.168.122.1:5000 RELEASE_REPO=fedora \
  just upload-container-local

# Examine the output for the OCI image location, e.g.:
# 192.168.122.2:5000/fedora/silverblue:rawhide.20260324.0
```

### Install the container image

On an already installed Silverblue system:

```
# Pin the currently deployed (and probably working) version
sudo ostree admin pin 0

sudo tee -a /etc/containers/registries.conf.d/localdev.conf <<EOF
[[registry]]
location="192.168.122.1:5000"
insecure=true
EOF

# Switch to your variant
sudo rpm-ostree rebase ostree-unverified-image:registry:192.168.122.1:5000/fedora/silverblue:rawhide.20260324.0

# Reboot and test!
```

See [URL format for ostree native containers](https://coreos.github.io/rpm-ostree/container/#url-format-for-ostree-native-containers) for details.

## Compose Methods and Outputs

There are a few different ways Fedora Atomic Desktop images are currently produced within Fedora's infrastructure.

### 1. Official Pungi Compose (OSTree Commit)

This is the traditional method for creating the official Fedora Atomic Desktops.

- **Source Repository**: `workstation-ostree-config` (this repository)
- **Compose Tool**: Fedora's official [Pungi](https://forge.fedoraproject.org/pungi/pungi) composer.
- **Output Type**: A classic OSTree commit.
- **Details**: This is the standard, officially supported output that is used to deliver updates to users.

### 2. Official Pungi Compose (OCI Image)

Fedora infrastructure also produces OCI (bootable container) images from the manifests in this repository.

- **Source Repository**: `workstation-ostree-config` (this repository)
- **Compose Tool**: Fedora's official [Pungi](https://forge.fedoraproject.org/pungi/pungi) composer.
- **Output Type**: An OCI container image.
- **Output Location**: `quay.io/fedora/fedora-<variant_name>` (e.g., `quay.io/fedora/fedora-silverblue`)
- **Details**: These official images are unsigned and do not have historical tags (e.g., `40.20240422.0`).

### 3. Unofficial CI-Test Builds (OCI Image)

For testing and development purposes, an unofficial set of OCI images are built using a separate repository that mirrors the manifests from this one but adds a GitLab CI pipeline.

- **Source Repository**: [gitlab.com/fedora/ostree/ci-test](https://gitlab.com/fedora/ostree/ci-test)
- **Compose Tool**: GitLab CI.
- **Output Type**: An OCI container image.
- **Output Location**: `quay.io/fedora-ostree-desktops/<variant_name>` (e.g., `quay.io/fedora-ostree-desktops/silverblue`)
- **Details**: These images are unofficial and intended for testing. Unlike the official OCI images, they are `cosign` signed, retain historical tags, and are subject to a 4-week expiry policy on the container registry.

The goal is to eventually use a similar CI pipeline-centric flow, with signing and historical tags, for the official releases.

## Syncing with Fedora Comps

[Fedora Comps](https://forge.fedoraproject.org/releng/fedora-comps.git) are
"XML files used by various Fedora tools to perform grouping of packages into
functional groups."

Changes to the comps files need to be regularly propagated to this repo so that
the Fedora Atomic variants are kept updated with the other desktop variants.

### Using `just`

If you have the `just` command installed, you can run `just comps` from a `git`
checkout of this repo to update the packages included in the Fedora Atomic
variants. Examine the changes and cross-reference them with PRs made to the
`fedora-comps` repo. Create a pull request with the changes and note any PRs
from `fedora-comps` in the commit message that are relevant to the changes you
have generated.

### Using `comps-sync.py` directly

If you don't have `just` installed or want to run the `comps-sync.py` script
directly, you need to have an up-to-date `git` checkout of
https://forge.fedoraproject.org/releng/fedora-comps and a `git` checkout of this repository.

Using the `comps-sync.py` script, provide the updated input XML file to examine
the changes as a dry-run:

`./comps-sync.py /path/to/fedora-comps/comps-f45.xml.in`

Examine the changes and cross-reference them with PRs made to the `fedora-comps`
repo. When you are satisfied that the changes are accurate and appear safe,
re-run the script with the `--save` option:

`./comps-sync.py --save /path/to/fedora-comps/comps-f45.xml.in`

Create a pull request with the changes and note any PRs from `fedora-comps`
in the commit message that are relevant to the changes you have generated.

## Branching instructions for new Fedora releases

Follow those steps during the Fedora branch process in Fedora:

### Fedora Ansible

Make a PR similar to
[ansible#1318](https://pagure.io/fedora-infra/ansible/pull-request/1318) in
[fedora-infra/ansible](https://pagure.io/fedora-infra/ansible).

### This repo

Use the branch recipe to create the new release branch and update the main
branch:

```
just branch
```

Push the new changes in both branches.

## Historical references

Building and testing instructions:

- https://dustymabe.com/2017/10/05/setting-up-an-atomic-host-build-server/
- https://dustymabe.com/2017/08/08/how-do-we-create-ostree-repos-and-artifacts-in-fedora/
- https://www.projectatomic.io/blog/2017/12/compose-custom-ostree/
- https://www.projectatomic.io/docs/compose-your-own-tree/

For some background, see:

- <https://fedoraproject.org/wiki/Workstation/AtomicWorkstation>
- <https://fedoraproject.org/wiki/Changes/WorkstationOstree>
- <https://fedoraproject.org/wiki/Changes/Silverblue>
- <https://fedoraproject.org/wiki/Changes/Fedora_Kinoite>

Note also this repo obsoletes https://pagure.io/atomic-ws
