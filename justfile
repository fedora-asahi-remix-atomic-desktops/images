# SPDX-FileCopyrightText: Fedora Atomic Desktops maintainers
# SPDX-License-Identifier: MIT

# Explicitely allow overriding variables and recipes from imported justfiles
set allow-duplicate-variables := true
set allow-duplicate-recipes := true

# Just doesn't have a native dict type, but quoted bash dictionary works fine
pretty_names := '(
    [silverblue-asahi-remix]="Silverblue Asahi Remix"
    [kinoite-asahi-remix]="Kinoite Asahi Remix"
    [base-atomic-asahi-remix]="Base Atomic Asahi Remix"
)'

# Define a 'release_ver' shortcut for use in recipes
release_ver := '''
"$(rpm-ostree compose tree --print-only "silverblue-asahi-remix.yaml" | jq -r '."mutate-os-release"')"
'''

# Define a 'is_rawhide' shortcut for use in recipes
is_rawhide := '''
"$(rpm-ostree compose tree --print-only "silverblue-asahi-remix.yaml" | jq -r '.repos[]')" == "fedora-rawhide"
'''

# Override validation recipe
validate:
    ./fedora-atomic-desktops/ci/validate

# Override the parent recipe to add our workarounds
compose-image variant="silverblue-asahi-remix":
    #!/bin/bash
    set -euxo pipefail

    declare -A pretty_names={{pretty_names}}
    variant={{variant}}
    variant_pretty=${pretty_names[$variant]-}
    if [[ -z $variant_pretty ]]; then
        echo "Unknown variant"
        exit 1
    fi

    just validate > /dev/null || (echo "Failed manifest validation" && exit 1)

    mkdir -p cache

    buildid="$(date '+%Y%m%d.0')"
    timestamp="$(date --iso-8601=sec)"
    echo "${buildid}" > .buildid

    version={{release_ver}}
    echo "Composing ${variant_pretty} ${version}.${buildid} ..."

    echo "Applying workarounds..."
    # Fedora Asahi Remix has its own kernel
    sed -i 's/  - kernel/  # - kernel/g' fedora-atomic-desktops/common.yaml
    # grubby is currently a dependency of update-m1n1
    sed -i 's/  - grubby/  # - grubby/g' fedora-atomic-desktops/common.yaml

    ARGS=(
        "--cachedir=cache"
        "--initialize"
        "--label=quay.expires-after=4w"
        "--max-layers=96"
        "--force-nocache"
    )
    # To debug with gdb, use: gdb --args ...
    CMD="rpm-ostree"
    if [[ ${EUID} -ne 0 ]]; then
        CMD="sudo rpm-ostree"
    fi

    ${CMD} compose image "${ARGS[@]}" \
        "${variant}.yaml" \
        "${variant}.ociarchive"

    echo "Removing workarounds..."
    sed -i 's/  # - kernel/  - kernel/g' fedora-atomic-desktops/common.yaml
    sed -i 's/  # - grubby/  - grubby/g' fedora-atomic-desktops/common.yaml

import 'fedora-atomic-desktops/justfile'
