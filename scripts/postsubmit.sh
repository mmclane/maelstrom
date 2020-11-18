#!/bin/env bash
set +e

# Packers should only build if there are files changed in the packer folder.
git show HEAD --name-status --format="%n" | grep packer\/
build_packer=$?

set -e

if [[ "${build_packer}" -eq "0" ]]; then
  echo Setup Environment
  source scripts/setup_env.sh

  cd packer/jmeter
  echo Start Packer
  packer build packer.json
else
  echo Skipping Packer Build
fi

