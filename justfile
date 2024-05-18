# SPDX-FileCopyrightText: Fedora Atomic Desktops maintainers
# SPDX-License-Identifier: MIT

# This is a justfile. See https://github.com/casey/just
# This is only used for local development. The builds made on the Fedora
# infrastructure are run via Pungi in a Koji runroot.

# Just doesn't have a native dict type, but quoted bash dictionary works fine
pretty_names := '(
    [silverblue]="Silverblue"
    [silverblue-asahi-remix]="Silverblue Asahi Remix"
    [kinoite]="Kinoite"
    [kinoite-nightly]="Kinoite"
    [kinoite-beta]="Kinoite"
    [kinoite-mobile]="Kinoite"
    [kinoite-asahi-remix]="Kinoite Asahi Remix"
    [sway-atomic]="Sway Atomic"
    [budgie-atomic]="Budgie Atomic"
    [xfce-atomic]="XFCE Atomic"
    [lxqt-atomic]="LXQt Atomic"
    [base-atomic]="Base Atomic"
    [base-atomic-asahi-remix]="Base Atomic Asahi Remix"
    [cosmic-atomic]="COSMIC Atomic"
)'

# subset of the map from https://pagure.io/pungi-fedora/blob/main/f/general.conf
volume_id_substitutions := '(
    [silverblue]="SB"
    [kinoite]="Kin"
    [kinoite-nightly]="Kin"
    [kinoite-beta]="Kin"
    [kinoite-mobile]="Kin"
    [sway-atomic]="SwA"
    [budgie-atomic]="BdA"
    [xfce-atomic]="XfA"
    [lxqt-atomic]="LxA"
    [base-atomic]="BsA"
    [cosmic-atomic]="CSMCA"
)'

# Define a 'release_ver' shortcut for use in recipes
release_ver := '''
"$(rpm-ostree compose tree --print-only "silverblue.yaml" | jq -r '."mutate-os-release"')"
'''

# Define a 'is_rawhide' shortcut for use in recipes
is_rawhide := '''
"$(rpm-ostree compose tree --print-only "silverblue.yaml" | jq -r '.repos[]')" == "fedora-rawhide"
'''

# Define a retry function for use in recipes
retry_function := '
retry() {
    if [[ "${#}" -lt 3 ]]; then
        echo "retry usage: <number of tries> <time between retries> <command> ..."
        return 1
    fi
    tries="${1}"
    sleep="${2}"
    shift 2
    for i in $(seq 1 ${tries}); do
        if [[ ${i} -gt 1 ]]; then
            # echo "[+] Command failed. Waiting for ${sleep} seconds"
            sleep ${sleep}
        fi
        # echo "[+] Running (try: ${i}): ${@}"
        "${@}" && r=0 && break || r=$?
    done
    return $r
}
'

# Default is to only validate the manifests
all: validate

# Basic validation to make sure the manifests are not completely broken
validate:
    ./ci/validate

branch:
    #!/bin/bash
    set -euo pipefail

    git checkout main

    version={{release_ver}}
    # recipe will exit if branching the repo fails, such as if branch already exists
    git branch f${version}
    sed -i "s/${version}/$(( version + 1 ))/g" comps-sync.py README.md
    sed -i "s/releasever: ${version}/releasever: $(( version + 1 ))/" common.yaml
    git add comps-sync.py common.yaml README.md
    git commit -m "Update main branch to $(( version + 1 ))"

    git checkout f${version}
    sed -i --follow-symlinks "/- fedora-rawhide/d" *.yaml
    sed -i --follow-symlinks "s/# - fedora/- fedora/" *.yaml
    sed -i --follow-symlinks "s/# - updates/- updates/" *.yaml
    sed -i "s/releasever_ref: \"rawhide\"/releasever_ref: \"${version}\"/" common.yaml
    git add *.yaml
    git commit -m "Update configs for branch f${version}"

# Sync the manifests with the content from the Fedora comps repo
# Use a shallow clone, pull latest changes and save the result by default
[arg("checkonly", short="c", long="checkonly", value="true"), arg("nopull", short="n", long="nopull", value="true")]
comps checkonly="false" nopull="false":
    #!/bin/bash
    set -euo pipefail

    if [[ ! -d fedora-comps ]]; then
        git clone --depth 1 https://forge.fedoraproject.org/releng/fedora-comps.git
    else
        if [[ "{{nopull}}" == "false" ]]; then
            pushd fedora-comps > /dev/null || exit 1
            if [[ "$(git rev-parse --is-shallow-repository)" == "true" ]]; then
                git fetch --unshallow
            else
                git fetch
            fi
            git reset --hard origin/main
            popd > /dev/null || exit 1
        fi
    fi

    save=""
    if [[ "{{checkonly}}" == "false" ]]; then
        save="--save"
    fi
    version={{release_ver}}
    ./comps-sync.py ${save} fedora-comps/comps-f${version}.xml.in

# Output the processed manifest for a given variant (defaults to Silverblue)
manifest variant="silverblue":
    #!/bin/bash
    set -euo pipefail

    rpm-ostree compose tree --print-only --repo=repo {{variant}}.yaml

# Perform dependency resolution for a given variant (defaults to Silverblue)
compose-dry-run variant="silverblue":
    #!/bin/bash
    set -euxo pipefail

    mkdir -p repo cache logs
    if [[ ! -f "repo/config" ]]; then
        pushd repo > /dev/null || exit 1
        ostree init --repo . --mode=bare-user
        popd > /dev/null || exit 1
    fi

    rpm-ostree compose tree --unified-core --repo=repo --dry-run {{variant}}.yaml

# Alias/shortcut for compose-image command
compose variant="silverblue": (compose-image variant)

# Compose a variant using the legacy non container path (defaults to Silverblue)
compose-legacy variant="silverblue":
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

    mkdir -p repo cache logs
    if [[ ! -f "repo/config" ]]; then
        pushd repo > /dev/null || exit 1
        ostree init --repo . --mode=archive-z2
        popd > /dev/null || exit 1
    fi
    # Set option to reduce fsync for transient builds
    ostree --repo=repo config set 'core.fsync' 'false'

    buildid="$(date '+%Y%m%d.0')"
    timestamp="$(date --iso-8601=sec)"
    echo "${buildid}" > .buildid

    version={{release_ver}}
    echo "Composing ${variant_pretty} ${version}.${buildid} ..."

    ARGS=(
        "--repo=repo"
        "--cachedir=cache"
        "--unified-core"
        "--force-nocache"
    )
    CMD="rpm-ostree"
    if [[ ${EUID} -ne 0 ]]; then
        CMD="sudo rpm-ostree"
    fi

    ${CMD} compose tree "${ARGS[@]}" \
        --add-metadata-string="version=${variant_pretty} ${version}.${buildid}" \
        "${variant}-ostree.yaml" \
            |& tee "logs/${variant}_${version}_${buildid}.${timestamp}.log"

    if [[ ${EUID} -ne 0 ]]; then
        sudo chown --recursive "$(id --user --name):$(id --group --name)" repo cache
    fi

    ostree summary --repo=repo --update

# Compose an Ostree Native Container OCI image
compose-image variant="silverblue":
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

# Clean up everything
clean-all:
    just clean-repo
    just clean-cache

# Only clean the ostree repo
clean-repo:
    rm -rf ./repo

# Only clean the package and repo caches
clean-cache:
    rm -rf ./cache

# Upload a container to a registry and sign it. Used in CI
upload-container variant="silverblue" arch="default":
    #!/bin/bash
    set -euxo pipefail

    {{retry_function}}

    variant={{variant}}
    arch={{arch}}

    declare -A pretty_names={{pretty_names}}
    variant_pretty=${pretty_names[$variant]-}
    if [[ -z $variant_pretty ]]; then
        echo "Unknown variant"
        exit 1
    fi

    if [[ "${CI}" != "true" ]]; then
        echo "Skipping: Not in CI"
        exit 1
    fi
    if [[ -z ${REGISTRY+x} ]] || [[ -z ${RELEASE_REPO+x} ]]; then
        echo "Skipping: No REGISTRY or RELEASE_REPO set"
        exit 1
    fi
    if [[ -z ${CI_REGISTRY_USER+x} ]] || [[ -z ${CI_REGISTRY_PASSWORD+x} ]]; then
        echo "Skipping: No CI_REGISTRY_USER or CI_REGISTRY_PASSWORD set"
        exit 1
    fi

    buildid=""
    if [[ -f ".buildid" ]]; then
        buildid="$(< .buildid)"
    else
        echo "Skipping: No '.buildid' file"
        exit 1
    fi

    # Login to the registry
    retry 5 60 skopeo login --username "${CI_REGISTRY_USER}" --password "${CI_REGISTRY_PASSWORD}" "${REGISTRY}"

    # Login to the registry again for cosign
    retry 5 60 skopeo login --username "${CI_REGISTRY_USER}" --password "${CI_REGISTRY_PASSWORD}" \
        --authfile="${HOME}/.docker/config.json" "${REGISTRY}"

    image="${REGISTRY}/${RELEASE_REPO}/${variant}"

    # Only append arch suffix if requested
    suffix=""
    if [[ ${arch} != "default" ]]; then
        suffix="-${arch}"
    fi

    # Support for the zstd:chunked format is not ready yet
    SKOPEO_ARGS=(
        "--retry-times" "3"
        "--dest-compress-format" "zstd"
    )

    version={{release_ver}}

    # Push fully versioned tag (major version, build date/id, arch)
    retry 5 60 skopeo copy "${SKOPEO_ARGS[@]}" \
        "oci-archive:${variant}.ociarchive" \
        "docker://${image}:${version}.${buildid}${suffix}"

    # Decode private key
    printenv "COSIGN_PRIVATE_KEY" > private.key.b64
    base64 --decode private.key.b64 > private.key

    # Sign images recursively
    retry 5 60 cosign sign -y --key private.key ${image}:${version}.${buildid}${suffix}

    # Cleanup private key
    rm private.key.b64 private.key

# Upload a container to an anonymous registry. Useful for local builds
upload-container-local variant="silverblue" arch="default":
    #!/bin/bash
    set -euxo pipefail

    {{retry_function}}

    variant={{variant}}
    arch={{arch}}

    declare -A pretty_names={{pretty_names}}
    variant_pretty=${pretty_names[$variant]-}
    if [[ -z $variant_pretty ]]; then
        echo "Unknown variant"
        exit 1
    fi

    if [[ -z ${REGISTRY+x} ]] || [[ -z ${RELEASE_REPO+x} ]]; then
        echo "Skipping: No REGISTRY or RELEASE_REPO set"
        exit 1
    fi

    buildid=""
    if [[ -f ".buildid" ]]; then
        buildid="$(< .buildid)"
    else
        echo "Skipping: No '.buildid' file"
        exit 1
    fi

    if [[ -n ${CI_REGISTRY_USER+x} ]] || [[ -n ${CI_REGISTRY_PASSWORD+x} ]]; then
        # Login to the registry
        retry 5 60 skopeo login --username "${CI_REGISTRY_USER}" --password "${CI_REGISTRY_PASSWORD}" "${REGISTRY}"
    fi

    image="${REGISTRY}/${RELEASE_REPO}/${variant}"

    # Only append arch suffix if requested
    suffix=""
    if [[ ${arch} != "default" ]]; then
        suffix="-${arch}"
    fi

    # Support for the zstd:chunked format is not ready yet
    SKOPEO_ARGS=(
        "--retry-times" "3"
        "--dest-tls-verify=false"
        "--dest-compress-format" "zstd"
    )

    version={{release_ver}}

    # Push fully versioned tag (major version, build date/id, arch)
    retry 5 60 skopeo copy "${SKOPEO_ARGS[@]}" \
        "oci-archive:${variant}.ociarchive" \
        "docker://${image}:${version}.${buildid}${suffix}"

    # Push under the rawhide name as needed
    if [[ {{is_rawhide}} ]]; then
        retry 5 60 skopeo copy "${SKOPEO_ARGS[@]}" \
            "oci-archive:${variant}.ociarchive" \
            "docker://${image}:rawhide.${buildid}${suffix}"
    fi

# Create a multi-arch manifest for a given variant, push it to a registry and sign it
multi-arch-manifest variant="silverblue":
    #!/bin/bash
    set -euxo pipefail

    {{retry_function}}

    variant={{variant}}

    declare -A pretty_names={{pretty_names}}
    variant_pretty=${pretty_names[$variant]-}
    if [[ -z $variant_pretty ]]; then
        echo "Unknown variant"
        exit 1
    fi

    if [[ "${CI}" != "true" ]]; then
        echo "Skipping: Not in CI"
        exit 1
    fi
    if [[ -z ${REGISTRY+x} ]] || [[ -z ${RELEASE_REPO+x} ]]; then
        echo "Skipping: No REGISTRY or RELEASE_REPO set"
        exit 1
    fi
    if [[ -z ${CI_REGISTRY_USER+x} ]] || [[ -z ${CI_REGISTRY_PASSWORD+x} ]]; then
        echo "Skipping: No CI_REGISTRY_USER or CI_REGISTRY_PASSWORD set"
        exit 1
    fi

    buildid=""
    if [[ -f ".buildid" ]]; then
        buildid="$(< .buildid)"
    else
        echo "Skipping: No '.buildid' file"
        exit 1
    fi

    # Login to the registry
    retry 5 60 skopeo login --username "${CI_REGISTRY_USER}" --password "${CI_REGISTRY_PASSWORD}" "${REGISTRY}"

    # Login to the registry again for cosign
    retry 5 60 skopeo login --username "${CI_REGISTRY_USER}" --password "${CI_REGISTRY_PASSWORD}" \
        --authfile="${HOME}/.docker/config.json" "${REGISTRY}"

    image="${REGISTRY}/${RELEASE_REPO}/${variant}"

    version={{release_ver}}

    # Create manifest with full version tags
    buildah manifest create "${image}:${version}.${buildid}" \
            "${image}:${version}.${buildid}-x86_64" \
            "${image}:${version}.${buildid}-aarch64"

    # Decode private key
    printenv "COSIGN_PRIVATE_KEY" > private.key.b64
    base64 --decode private.key.b64 > private.key

    # Push fully versioned dual arch manifest tag (major version, build date/id)
    retry 5 60 buildah manifest push \
        "${image}:${version}.${buildid}" \
        "docker://${image}:${version}.${buildid}"

    # Push under the rawhide name as needed
    if [[ {{is_rawhide}} ]]; then
        retry 5 60 buildah manifest push \
            "${image}:${version}.${buildid}" \
            "docker://${image}:rawhide.${buildid}"
    fi

    # Sign manifest
    retry 5 60 cosign sign -y --key private.key ${image}:${version}.${buildid}

    # Update "un-versioned" tag (only major version)
    retry 5 60 buildah manifest push \
        "${image}:${version}.${buildid}" \
        "docker://${image}:${version}"

    # Push under the rawhide name as needed
    if [[ {{is_rawhide}} ]]; then
        retry 5 60 buildah manifest push \
            "${image}:${version}.${buildid}" \
            "docker://${image}:rawhide"
    fi

    # Sign manifest
    retry 5 60 cosign sign -y --key private.key ${image}:${version}

    if [[ "${variant}" == "kinoite-nightly" ]]; then
        # Update latest tag for kinoite-nightly only
        buildah manifest push \
            "${image}:${version}.${buildid}" \
            "docker://${image}:latest"
        # Sign manifest
        cosign sign -y --key private.key ${image}:latest
    fi

    # Cleanup private key
    rm private.key.b64 private.key
