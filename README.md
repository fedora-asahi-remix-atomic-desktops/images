# Unofficial and experimental Fedora Asahi Atomic Remix Bootable Container images

**Those are unofficial, experimental Bootable Container images of Silverblue
and Kinoite using the packages from the Fedora Asahi Remix project.**

**For the official Fedora Asahi Remix project, see
[asahilinux.org/fedora](https://asahilinux.org/fedora/).**

**This project is a work in progress, is incomplete and not endorsed by the
Asahi developers.**

## Overview

This repo is a fork of the
[upstream manifests for the Fedora Atomic Desktops](https://pagure.io/workstation-ostree-config)
with GitHub Actions and minor changes on top to enable us to build experimental
Bootable Container images for Apple Silicon based on the work of the Asahi
project.

This project is a fork of the upstream sources and will be kept up to date with
changes from upstream. Thus expect frequent rebases and `push --force`. PRs
will likely be merged manually for a while.

## How to use

TODO

## Images

This project builds the following images for the Fedora releases currently
supported by the Asahi project (may not always be the latest release):

- Fedora Silverblue Asahi Remix:
    - Unofficial build based on the official Silverblue variant
    - [quay.io/repository/fedora-asahi-atomic-remix/silverblue](https://quay.io/repository/fedora-asahi-atomic-remix/silverblue?tab=tags)
- Fedora Kinoite Asahi Remix:
    - Unofficial build based on the official Kinoite variant
    - [quay.io/repository/fedora-asahi-atomic-remix/kinoite](https://quay.io/repository/fedora-asahi-atomic-remix/kinoite?tab=tags)

## Container image signatures

The images are signed using cosign and can be verified using the public key
included in the repo.
