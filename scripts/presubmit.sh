#!/bin/env bash
set -ex

echo Setup Environment
source scripts/setup_env.sh

cd ${WORKSPACE}/terraform/jmeter
terraform init

# This validates that we never use azure classic provider
set +e
azure_classic_used=$(terraform providers | grep -w -c "provider.azure")
set -e
if [ "0" -ne "${azure_classic_used}" ]; then
  echo "Azure classic provider referenced, this is not supported"
  echo "Please upgrade to azurerm: https://www.terraform.io/docs/providers/azurerm/index.html"
  exit 1
fi



cd ${WORKSPACE}/packer/jmeter

echo Start Packer
packer validate packer.json
packer validate docker-packer.json
##
# TODO: Talk to core services to ask how they are are using docker
# in the jenkins build server, so that we can have CI on our image
# builds in the future.
# packer build docker-packer.json
##

