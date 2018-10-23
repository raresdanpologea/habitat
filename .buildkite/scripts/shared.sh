#!/bin/bash

# Download public and private keys for the "core" origin from Builder.
#
# Currently relies on a global variable `hab_binary` being set, since
# in the Linux build process, we need to switch binaries mid-way
# through the pipeline. As we bring more platforms into play, this may
# change. FYI.
import_keys() {
    echo "--- :key: Downloading 'core' public keys from Builder"
    ${hab_binary:?} origin key download core
    echo "--- :closed_lock_with_key: Downloading latest 'core' secret key from Builder"
    ${hab_binary:?} origin key download \
        --auth="${HAB_AUTH_TOKEN}" \
        --secret \
        core
    # TODO (CM): delete the secret key later?
}

# Given a platform target, channel, package name, and optional
# version, return the fully-qualified identifier of the latest such
# `core` package in Builder.
#
# Examples:
#
#  latest_from_builder x86_64-linux stable hab 0.58.0
#  # => core/hab/0.58.0/20180629144346
#
#  latest_from_builder x86_64-windows stable hab-launcher
#  # => core/hab-launcher/7241/20180321094917
latest_from_builder() {
    target="${1}"
    channel="${2}"
    package_name="${3}"
    version="${4:-}"

    if [ -z "${version}" ]; then
        url="https://bldr.habitat.sh/v1/depot/channels/core/${channel}/pkgs/${package_name}/latest?target=${target}"
    else
        url="https://bldr.habitat.sh/v1/depot/channels/core/${channel}/pkgs/${package_name}/${version}/latest?target=${target}"
    fi

    ident=$(curl -s "${url}" | jq -r '.ident | .origin + "/" + .name + "/" + .version + "/" + .release')
    echo "${ident}"
}

# Abstracts the logic (such as it is) for whether we're doing a "fake"
# release or not.

set_fake_release() {
    local release=${1}
    buildkite-agent meta-data set fake-release "${release}"
}

is_fake_release() {
    buildkite-agent meta-data exists fake-release
}

get_fake_release() {
    buildkite-agent meta-data get fake-release
}

# Until we have built both a new core/hab _and_ a new core/hab-studio
# package, we should continue to use the `hab` binary provided on our
# Buildkite builders (managed by Release Engineering) (these should be
# the latest stable release, btw).
#
# Once we have bootstrapped ourselves enough, however, we should
# switch subsequent builds to use the new hab, which in turn uses the
# new studio.
set_hab_binary() {
    echo "--- :thinking_face: Determining which 'hab' binary to use"
    # This ensure the hab cli we use going forward has the correct
    # ActiveTarget. Otherwise, if we were to attempt to install an
    # `x86_64-linux-kernel2` package with the `hab` on our path, it
    # would result in an error and fail the build.
    if [[ "$BUILD_PKG_TARGET" == "x86_64-linux-kernel2" ]]; then
        install_hab_kernel2_binary
        hab_binary="$(which hab-x86_64-linux-kernel2)"
    else 
        hab_binary="$(which hab)"
    fi 

    if buildkite-agent meta-data exists hab-version &&
            buildkite-agent meta-data exists studio-version; then
        echo "Buildkite metadata found; installing new versions of 'core/hab' and 'core/hab-studio'"
        # By definition, these will be fully-qualified identifiers,
        # and thus do not require a `--channel` option. However, they
        # should be coming from the release channel, and should be the
        # same packages built previously in this same release pipeline.
        hab_ident=$(buildkite-agent meta-data get hab-version)

        # Note that we are explicitly not binlinking here; this is to
        # prevent accidentally polluting the builder for any future
        # runs that may take place on it.
        sudo hab pkg install "${hab_ident}"
        sudo hab pkg install "$(buildkite-agent meta-data get studio-version)"
        hab_binary="/hab/pkgs/${hab_ident}/bin/hab"
        declare -g new_studio=1
    else
        echo "Buildkite metadata NOT found; using previously-installed hab binary: $hab_binary"
    fi
    declare -g hab_binary
    echo "--- :habicat: Using $(${hab_binary} --version)"
}

# This installation step is a temporary shim until we have done at
# least one release. Once we have a release, we can update ci-studio-common
# to fetch this binary from bintray using the install.sh script and the install
# step is no longer needed. Until then, we need to fetch it from our 
# bootstrap pipeline. 
install_hab_kernel2_binary() {
    local hab_src_url tempdir
    hab_src_url="http://s3-us-west-2.amazonaws.com/habitat-bootstrap-artifacts/x86_64-linux-kernel2/stage2/hab-stage2-x86_64-linux-kernel2-latest"
    tempdir=$(mktemp -d hab-kernel2-XXXX)

    pushd $tempdir >/dev/null
    curl "$hab_src_url" -o hab-x86_64-linux-kernel2
    sudo mv hab-x86_64-linux-kernel2 /bin/hab-x86_64-linux-kernel2
    sudo chmod +x /bin/hab-x86_64-linux-kernel2
    popd 
    rm -rf "$tempdir" >/dev/null
}
