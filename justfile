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

import 'fedora-atomic-desktops/justfile'
