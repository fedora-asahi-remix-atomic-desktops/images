#!/bin/bash
# SPDX-License-Identifier: MIT

set -euo pipefail
# set -x

variants=(
    'silverblue'
    'kinoite'
    'kinoite-mobile'
    'sway-atomic'
    'xfce-atomic'
    'lxqt-atomic'
    'budgie-atomic'
    'base-atomic'
    'cosmic-atomic'
)

branch="$(git rev-parse --abbrev-ref HEAD)"
release=""
if [[ "${branch}" == "main" ]] || [[ -f "fedora-rawhide.repo" ]]; then
    release="rawhide"
else
    release="$(rpm-ostree compose tree --print-only --repo=repo silverblue.yaml | jq -r '."mutate-os-release"')"
fi

{
cat <<EOF
# SPDX-License-Identifier: MIT

# Only used in https://gitlab.com/fedora/ostree/ci-test
# For tests running in the Fedora infrastructure, see .zuul.yaml and
# https://fedoraproject.org/wiki/Zuul-based-ci

# See: https://gitlab.com/fedora/ostree/buildroot
image: quay.io/fedora-ostree-desktops/buildroot:$release

# As those are not official images, we build all available variants.
# We build the images for merge requests, we push and sign them for commits
# pushed to release branches and scheduled pipelines.

stages:
  - build
  - merge
EOF

for variant in "${variants[@]}"; do
cat <<EOF

mr-$variant-x86_64:
  stage: build
  script:
    - just compose-image $variant
  tags:
    - saas-linux-small-amd64
  rules:
    - if: \$CI_PIPELINE_SOURCE == "merge_request_event"

mr-$variant-aarch64:
  stage: build
  script:
    - just compose-image $variant
  tags:
    - saas-linux-small-arm64
  rules:
    - if: \$CI_PIPELINE_SOURCE == "merge_request_event"

build-$variant-x86_64:
  stage: build
  script:
    - just compose-image $variant
    - just upload-container $variant x86_64
  tags:
    - saas-linux-small-amd64
  rules:
    - if: \$CI_COMMIT_BRANCH == "$branch" && (\$CI_PIPELINE_SOURCE == "push" || \$CI_PIPELINE_SOURCE == "schedule")

build-$variant-aarch64:
  stage: build
  script:
    - just compose-image $variant
    - just upload-container $variant aarch64
  tags:
    - saas-linux-small-arm64
  rules:
    - if: \$CI_COMMIT_BRANCH == "$branch" && (\$CI_PIPELINE_SOURCE == "push" || \$CI_PIPELINE_SOURCE == "schedule")

merge-$variant:
  stage: merge
  script:
    - just multi-arch-manifest $variant
    - just sign $variant
  needs: ["build-$variant-x86_64", "build-$variant-aarch64"]
  tags:
    - saas-linux-small-amd64
  rules:
    - if: \$CI_COMMIT_BRANCH == "$branch" && (\$CI_PIPELINE_SOURCE == "push" || \$CI_PIPELINE_SOURCE == "schedule")
EOF
done
} > .gitlab-ci.yml
