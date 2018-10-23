#!/bin/bash

# We need to upload (but not publish) artifacts to Bintray right now.

set -euo pipefail

source .buildkite/scripts/shared.sh

set_hab_binary

# TODO: bintray user = chef-releng-ops!

if is_fake_release; then
    bintray_repository=unstable
else
    bintray_repository=stable
fi
echo "--- Preparing to push artifacts to the ${bintray_repository} Bintray repository"

channel=$(buildkite-agent meta-data get "release-channel")

# TODO (CM): extract set_hab_binary function to a common library and
# use it here

echo "--- :habicat: Installing core/hab-bintray-publish from '${channel}' channel"
sudo ${hab_binary} pkg install \
     --channel="${channel}" \
     core/hab-bintray-publish

# TODO (CM): determine artifact name for given hab identifier
#            could save this as metadata, or just save the artifact in
#            BK directly

echo "--- :habicat: Uploading core/hab to Bintray"

# TODO (CM): Continue with this approach, or just grab the artifact
# that we built out of BK?
#
# If we use `hab pkg install` we know we'll get the artifact for our
# platform.
#
# If we use Buildkite, we can potentially upload many different
# platform artifacts to Bintray from a single platform (e.g., upload
# Windows artifacts from Linux machines.)
sudo ${hab_binary} pkg install core/hab --channel="${channel}"

hab_artifact=$(buildkite-agent meta-data get "hab-artifact")

# We upload to the stable channel, but we don't *publish* until
# later.
#
# -s = skip publishing
# -r = the repository to upload to
sudo HAB_BLDR_CHANNEL="${channel}" \
     BINTRAY_USER="${BINTRAY_USER}" \
     BINTRAY_KEY="${BINTRAY_KEY}" \
     BINTRAY_PASSPHRASE="${BINTRAY_PASSPHRASE}" \
     ${hab_binary} pkg exec core/hab-bintray-publish \
         publish-hab \
         -s \
         -r "${bintray_repository}" \
         "/hab/cache/artifacts/${hab_artifact}"

source results/last_build.env
shasum=$(awk '{print $1}' "results/${pkg_artifact:?}.sha256sum")
cat << EOF | buildkite-agent annotate --style=success --context=bintray-hab
<h3>Habitat Bintray Binary (${pkg_target:?})</h3>
Artifact: <code>${pkg_artifact}</code>
<br/>
SHA256: <code>${shasum}</code>
EOF
