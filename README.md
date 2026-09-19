# Unofficial and experimental Fedora Asahi Remix Atomic Desktops Bootable Container images

**Those are unofficial, experimental Bootable Container images of Silverblue,
Kinoite and Base Atomic using the packages from the Fedora Asahi Remix
project.**

**For the official Fedora Asahi Remix project, see
[asahilinux.org/fedora](https://asahilinux.org/fedora/).**

**This project is a work in progress, is incomplete and not endorsed by the
Asahi developers.**

## Overview

This repo reuses the
[upstream manifests for the Fedora Atomic Desktops](https://forge.fedoraproject.org/atomic-desktops/config)
(pulled in as a git submodule in `fedora-atomic-desktops/`) and adds a thin
layer on top to build experimental Bootable Container images for Apple Silicon
based on the work of the Asahi project:

- `*-asahi-remix.yaml`: the variant manifests (`silverblue`, `kinoite`,
  `base-atomic`). Each one includes the matching upstream manifest plus
  `repos.yaml` and `asahi-remix.yaml`.
- `asahi-remix.yaml`: the Asahi specific packages (kernel, m1n1/U-Boot
  updaters, firmware, audio, ...) and the Asahi Copr / hotfixes repos.
- `repos.yaml`: the Fedora repos to use for the branch (see
  [Branches](#branches) below).
- `*.repo`: repo definitions for the Asahi Copr and hotfixes repos.
  `fedora.repo` is a symlink to the upstream one in the submodule.
- `justfile`: imports the upstream `justfile` and overrides `compose-image` to
  apply the Asahi specific workarounds (the Asahi kernel replaces the Fedora
  `kernel` package and `grubby` is pulled in by `update-m1n1`).
- `.github/workflows/bootable-containers.yml`: the GitHub Actions workflow
  that builds, pushes and signs the images.

PRs are merged manually.

## Branches

- `main`: tracks Fedora Rawhide (`repos.yaml` uses `fedora-rawhide` and the
  submodule follows the upstream `main` branch). Rawhide images are **not**
  built as some Asahi packages are not available for it. This branch holds
  the workflow that does the daily builds: for each Fedora release in the
  `version` matrix, it checks out the matching `f<version>` branch and builds
  it in the `quay.io/fedora-ostree-desktops/buildroot:<version>` container.
- `f44`, `f43`, ...: one branch per supported Fedora release. On those
  branches `repos.yaml` uses the `fedora` and `updates` repos, the submodule
  is pinned to the matching upstream `f<version>` branch and the workflow only
  runs test builds for pull requests (no push).

## Bumping to a new Fedora release

Prerequisites for a new Fedora release `NN`:

- The upstream `quay.io/fedora-ostree-desktops/buildroot:NN` container image
  must exist.
- The upstream manifests must have an `fNN` branch.
- The Asahi Copr repos (`@asahi/kernel`, `@asahi/mesa`, `@asahi/u-boot`,
  `@asahi/fedora-remix-branding`, `@asahi/fedora-remix-scripts`) and the
  Asahi hotfixes repo (see `fedora-asahi-remix-hotfixes.repo`) must have
  builds for `fedora-NN-aarch64`. This usually happens once the Asahi project
  officially supports the release.

Then:

1. Create the release branch from `main`:

   ```
   $ git checkout -b fNN origin/main
   ```

2. Switch the submodule to the matching upstream branch and update it:

   ```
   $ git submodule set-branch --branch fNN fedora-atomic-desktops
   $ git submodule update --init --remote fedora-atomic-desktops
   $ git add .gitmodules fedora-atomic-desktops
   ```

3. Replace `fedora-rawhide` with `fedora` and `updates` in `repos.yaml`.

4. Update `.github/workflows/bootable-containers.yml` on the branch to only
   run on `pull_request` for `fNN`, build in `buildroot:NN` and drop the
   `version` matrix and the push/sign steps (compare `f44` with `main`).

5. Run `just validate` and a test build (see below), then push the branch and
   open a PR against `main` adding `'NN'` to the `version` matrix in the
   workflow (and dropping releases that are EOL).

## Building locally

Builds must be done on an aarch64 Fedora system (or in the
`quay.io/fedora-ostree-desktops/buildroot:<version>` container with
`--privileged`) with `just`, `rpm-ostree` and `jq` installed. The GPG keys
for the Asahi repos are needed to verify the packages:

```
$ sudo dnf copr enable -y @asahi/fedora-remix-branding
$ sudo dnf install -y asahi-repos
```

Then, on the branch for the release you want to build:

```
$ git clone --branch f44 --recurse-submodules https://github.com/fedora-asahi-remix-atomic-desktops/images.git
$ cd images
# Validate manifests and print the resolved manifest (fast, no download)
$ just validate
$ rpm-ostree compose tree --print-only base-atomic-asahi-remix.yaml
# Build the Bootable Container image (slow, needs root)
$ just compose-image base-atomic-asahi-remix
```

This produces `base-atomic-asahi-remix.ociarchive`, which you can inspect
with `skopeo inspect oci-archive:base-atomic-asahi-remix.ociarchive` or push
to a registry with `skopeo copy`.

## How to use

You need an existing Fedora Asahi Remix installation on your Apple Silicon Mac
(this project does not provide an installer) as the Asahi boot chain
(m1n1, U-Boot) is setup by the official installer. These images are then
meant to be used with `bootc` or `rpm-ostree` on a Fedora Atomic Desktop
system.

Follow the [signature verification setup](#container-image-signatures)
below, then rebase to the desired variant and Fedora release, for example:

```
$ sudo bootc switch quay.io/fedora-asahi-remix-atomic-desktops/base-atomic:44
```

or with `rpm-ostree`:

```
$ sudo rpm-ostree rebase ostree-image-signed:registry:quay.io/fedora-asahi-remix-atomic-desktops/base-atomic:44
```

Reboot to the new deployment. If it does not work, boot the previous
deployment from the bootloader menu and run `sudo bootc rollback` (or
`sudo rpm-ostree rollback`).

## Images

This project builds the following images for the Fedora releases currently
supported by the Asahi project (may not always be the latest release). The
releases currently built are listed in the `version` matrix of the workflow
on the `main` branch and are available as the `<release>` tag (e.g. `44`)
along with dated `<release>.<YYYYMMDD>.0` tags:

- Fedora Asahi Remix Silverblue:
    - Unofficial build based on the official Silverblue variant
    - [quay.io/repository/fedora-asahi-remix-atomic-desktops/silverblue](https://quay.io/repository/fedora-asahi-remix-atomic-desktops/silverblue?tab=tags)
- Fedora Asahi Remix Kinoite:
    - Unofficial build based on the official Kinoite variant
    - [quay.io/repository/fedora-asahi-remix-atomic-desktops/kinoite](https://quay.io/repository/fedora-asahi-remix-atomic-desktops/kinoite?tab=tags)
- Fedora Asahi Remix Base Atomic:
    - Unofficial build based on the unofficial Fedora Base Atomic variant
    - No desktop environment included
    - [quay.io/repository/fedora-asahi-remix-atomic-desktops/base-atomic](https://quay.io/repository/fedora-asahi-remix-atomic-desktops/base-atomic?tab=tags)

## Container image signatures

The images are signed using cosign and can be verified using the public key
included in the repo. Here is how to setup container image signature
verification:

- Get the public key from this repo and install it:

  ```
  $ sudo mkdir /etc/pki/containers
  $ curl --location -O "https://github.com/fedora-asahi-remix-atomic-desktops/images/raw/refs/heads/main/quay.io-fedora-asahi-atomic-remix.pub"
  $ sudo cp quay.io-fedora-asahi-atomic-remix.pub /etc/pki/containers/quay.io-fedora-asahi-remix-atomic-desktops.pub
  $ sudo restorecon -RFv /etc/pki/containers
  $ rm quay.io-fedora-asahi-atomic-remix.pub
  ```

- Add registry configuration to get sigstore signatures:

  ```
  $ cat /etc/containers/registries.d/quay.io-fedora-asahi-remix-atomic-desktops.yaml
  docker:
    quay.io/fedora-asahi-remix-atomic-desktops
      use-sigstore-attachments: true
  $ sudo restorecon -RFv /etc/containers/registries.d
  ```

- Add config to the container fetching policy:

  ```
  {
      "default": [{ "type": "reject" }],
      "transports": {
          "docker": {
              "quay.io/fedora-asahi-remix-atomic-desktops": [
                  {
                      "type": "sigstoreSigned",
                      "keyPath": "/etc/pki/containers/quay.io-fedora-asahi-remix-atomic-desktops.pub",
                      "signedIdentity": {
                          "type": "matchRepository"
                      }
                  }
              ],
              "": [{ "type": "insecureAcceptAnything" }]
          },
          "containers-storage": {
              "": [{ "type": "insecureAcceptAnything" }]
          },
          "oci": {
              "": [{ "type": "insecureAcceptAnything" }]
          },
          "oci-archive": {
              "": [{ "type": "insecureAcceptAnything" }]
          },
          "docker-daemon": {
              "": [{ "type": "insecureAcceptAnything" }]
          }
      }
  }
  ```

- Rebase:

  ```
  $ sudo rpm-ostree rebase ostree-image-signed:registry:quay.io/fedora-asahi-remix-atomic-desktops/silverblue:44
  ```
