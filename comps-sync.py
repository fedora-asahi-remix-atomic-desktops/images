#!/usr/bin/python3

# SPDX-FileCopyrightText: Fedora Atomic Desktops maintainers
# SPDX-License-Identifier: MIT

'''
Usage: ./comps-sync.py [--save] /path/to/comps-f45.xml.in

Filter and sync packages from comps groups into rpm-ostree manifests. The sync
will remove packages from the manifests which are not mentioned in comps and
add missing packages from comps to the manifests.

Use --save to write the changes and always exit with a 0 return code.
Otherwise, exit with a non zero return code if any changes are needed.
'''

import argparse
import re
import sys
import yaml
import libcomps

ARCHES = ("x86_64", "aarch64")

def fatal(msg):
    '''Print the error message and exit.'''
    print(msg, file = sys.stderr)
    sys.exit(1)

def format_pkgtype(pkgtype):
    '''Return a printable string from a libcomps package type.'''
    if pkgtype == libcomps.PACKAGE_TYPE_DEFAULT:
        return 'default'
    if pkgtype == libcomps.PACKAGE_TYPE_MANDATORY:
        return 'mandatory'
    assert False

def write_manifest(fpath, pkgs):
    '''Write the package list in a manifest.'''
    with open(fpath, 'w', encoding='UTF-8') as f:
        f.write("# DO NOT EDIT! This content is generated from comps-sync.py\n")
        f.write("packages:\n")
        for pkg in sorted(pkgs['all']):
            f.write(f'  - {pkg}\n')
        for arch in ARCHES:
            if pkgs[arch]:
                f.write(f"packages-{arch}:\n")
                for pkg in sorted(pkgs[arch]):
                    f.write(f'  - {pkg}\n')
        print(f'Wrote {fpath}')

def is_exclude_listed(pkgname, exclude_list_regexp):
    '''Check if pkgname is in the exclude list.'''
    for br in exclude_list_regexp:
        if br.match(pkgname):
            return True
    return False

def load_packages_from_manifest(manifest_path):
    '''Load the list of packages from an rpm-ostree manifest file.'''
    with open(manifest_path, encoding='UTF-8') as f:
        manifest = yaml.safe_load(f)
    manifest_packages = {}
    manifest_packages['all'] = set(manifest['packages'])
    for arch in ARCHES:
        if f'packages-{arch}' in manifest:
            manifest_packages[arch] = set(manifest[f'packages-{arch}'])
        else:
            manifest_packages[arch] = set()
    return manifest_packages

def load_packages_from_comps_group(comps_group_packages, comps, groupname, exclude_list, exclude_list_regexp):
    '''Load packages from a comps group, storing the group, type and arches.'''
    for arch in ARCHES:
        filtered = comps.arch_filter([arch])
        group = filtered.groups_match(id=groupname)[0]
        for pkg in group.packages:
            pkgname = pkg.name
            if pkg.type not in (libcomps.PACKAGE_TYPE_DEFAULT,
                                libcomps.PACKAGE_TYPE_MANDATORY):
                continue
            if pkgname in exclude_list or is_exclude_listed(pkgname, exclude_list_regexp):
                continue
            pkgdata = comps_group_packages.get(pkgname)
            if pkgdata is None:
                comps_group_packages[pkgname] = pkgdata = (pkg.type, set([groupname]), set([arch]))
            if (pkgdata[0] == libcomps.PACKAGE_TYPE_DEFAULT and
                pkg.type == libcomps.PACKAGE_TYPE_MANDATORY):
                comps_group_packages[pkgname] = pkgdata = (pkg.type, pkgdata[1], pkgdata[2])
            pkgdata[1].add(groupname)
            pkgdata[2].add(arch)
    return comps_group_packages

def compare_comps_manifest_package_lists(comps_group_pkgs, manifest_packages):
    '''Compare the list of packages in the comps and the manifests and return the difference.'''
    # Look for packages in the manifest but not in the comps
    comps_unknown = set()
    for arch in manifest_packages:
        for pkg in manifest_packages[arch]:
            if arch == "all":
                if pkg in comps_group_pkgs and set(comps_group_pkgs[pkg][2]) == set(ARCHES):
                    continue
            else:
                if pkg in comps_group_pkgs and arch in comps_group_pkgs[pkg][2]:
                    continue
            comps_unknown.add((pkg, arch))

    # Look for packages in comps but not in the manifest
    pkgs_added = {}
    for (pkg, pkgdata) in comps_group_pkgs.items():
        if set(ARCHES) == set(pkgdata[2]):
            if pkg not in manifest_packages['all']:
                pkgs_added[pkg] = pkgdata
        else:
            for arch in pkgdata[2]:
                if pkg not in manifest_packages[arch]:
                    if pkg not in pkgs_added:
                        pkgs_added[pkg] = (pkgdata[0], pkgdata[1], set([arch]))
                    else:
                        pkgs_added[pkg][2].add(arch)

    return comps_unknown, pkgs_added

def update_manifests_from_groups(comps, groups, path, variant, save, comps_exclude_list, comps_exclude_list_all):
    manifest_packages = load_packages_from_manifest(path)

    comps_group_pkgs = {}
    for group in groups:
        exclude_list = comps_exclude_list.get(group, set())
        comps_group_pkgs = load_packages_from_comps_group(comps_group_pkgs, comps, group, exclude_list, comps_exclude_list_all)

    (comps_unknown, pkgs_added) = compare_comps_manifest_package_lists(comps_group_pkgs, manifest_packages)

    n_manifest_new = len(comps_unknown)
    n_comps_new = len(pkgs_added)

    if variant == "common":
        print(f'Syncing common packages:\t+{n_comps_new}, -{n_manifest_new}')
    else:
        print(f'Syncing packages for {variant}:\t+{n_comps_new}, -{n_manifest_new}')
    if n_manifest_new != 0:
        for (pkg, arch) in sorted(comps_unknown, key = lambda x: x[0]):
            manifest_packages[arch].remove(pkg)
            print(f'  - {pkg} (arches: {arch})')
    if n_comps_new != 0:
        for pkg in sorted(pkgs_added):
            (req, groups, arches) = pkgs_added[pkg]
            if set(ARCHES) == arches:
                manifest_packages['all'].add(pkg)
                print('  + {} ({}, groups: {}, arches: all)'.format(pkg, format_pkgtype(req), ', '.join(groups)))
            else:
                for arch in arches:
                    manifest_packages[arch].add(pkg)
                print('  + {} ({}, groups: {}, arches: {})'.format(pkg, format_pkgtype(req), ', '.join(groups), ', '.join(arches)))

    if (n_manifest_new > 0 or n_comps_new > 0):
        if save:
            write_manifest(path, manifest_packages)
        return 1
    return 0

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--save", help="Write changes to manifests", action='store_true')
    parser.add_argument("src", help="Source path")

    args = parser.parse_args()

    with open('comps-sync-exclude-list.yml', encoding='UTF-8') as f:
        doc = yaml.safe_load(f)
        comps_exclude_list = doc['exclude_list']
        comps_exclude_list_groups = doc['exclude_list_groups']
        comps_desktop_exclude_list = doc['desktop_exclude_list']
        comps_exclude_list_all = [re.compile(x) for x in doc['exclude_list_all_regexp']]

    # Parse comps, and build up a set of all packages so we can find packages not
    # listed in comps *at all*, beyond just the workstation environment.
    comps = libcomps.Comps()
    comps.fromxml_f(args.src)

    # Parse the workstation-product environment to get the list of comps groups to
    # get packages from.
    groups = []
    for gid in comps.environments['workstation-product-environment'].group_ids:
        if gid.name in comps_exclude_list_groups:
            continue
        groups.append(gid.name)

    # Always include the packages from the workstation-ostree-support group
    groups.append('workstation-ostree-support')

    # Return code indicates if changes have or would have been done
    ret = 0

    ret += update_manifests_from_groups(comps, groups, 'packages/common.yaml', "common", args.save, comps_exclude_list, comps_exclude_list_all)

    # List of comps groups used for each variant
    variant_comps_groups = {
        "budgie-atomic": ["budgie-desktop", "budgie-desktop-apps", "base-x"],
        "cosmic-atomic": ["cosmic-desktop", "cosmic-desktop-apps", "base-graphical"],
        "kinoite": ["kde-desktop", "base-graphical"],
        "kinoite-mobile": ["kde-mobile", "kde-mobile-apps", "base-graphical"],
        "silverblue": ["gnome-desktop", "base-graphical"],
        "sway-atomic": ["swaywm", "swaywm-extended", "base-graphical"],
    }

    # Generate treefiles for all variants
    for variant, groups in variant_comps_groups.items():
        print()
        ret += update_manifests_from_groups(comps, groups, f'packages/{variant}.yaml', variant, args.save, comps_desktop_exclude_list, comps_exclude_list_all)

    if not args.save and ret != 0:
        sys.exit(1)

if __name__ == "__main__":
    main()
