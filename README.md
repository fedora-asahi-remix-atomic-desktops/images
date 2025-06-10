# Unofficial and experimental Fedora Asahi Remix Atomic Desktops Bootable Container images

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
  $ curl -location -O "https://github.com/fedora-asahi-remix-atomic-desktops/images/raw/refs/heads/main/quay.io-fedora-asahi-remix-atomic-desktops.pub"
  $ sudo cp quay.io-fedora-asahi-remix-atomic-desktops.pub /etc/pki/containers/
  $ sudo restorecon -RFv /etc/pki/containers
  $ rm quay.io-fedora-asahi-remix-atomic-desktops.pub
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
  $ sudo rpm-ostree rebase ostree-image-signed:registry:quay.io/fedora-asahi-remix-atomic-desktops/silverblue:42
  ```
