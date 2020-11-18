#!/usr/bin/env bash
set -euo pipefail
echo "Preparing the environment"

readonly PACKER_VERSION="1.2.3"
readonly INSTALL_DIR="bin"
readonly DOWNLOAD_DIR="."

##############################################
# Download and Setup Packer
##############################################
# TODO: Modify this script so that it downloads from Criteo filers.
echo "Installing Packer"
if [ "$(uname)" == "Darwin" ]; then
  readonly TARGET_OS=darwin
elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
  readonly TARGET_OS=linux
fi

readonly PACKER_DOWNLOAD_URL="https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_${TARGET_OS}_amd64.zip"
readonly PACKER_DOWNLOADED_FILE="$DOWNLOAD_DIR/packer-${PACKER_VERSION}.zip"

readonly TERRAFORM_VERSION="0.11.3"
readonly TF_DOWNLOADED_FILE="${DOWNLOAD_DIR}/terraform_${TERRAFORM_VERSION}.zip"
readonly TF_DOWNLOAD_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"

check_env () {
  curl_cmd=`which curl`
  unzip_cmd=`which unzip`

  if [ -z "$curl_cmd" ]; then
    error "curl does not appear to be installed. Please install and re-run this script."
  fi

  if [ -z "$unzip_cmd" ]; then
    error "unzip does not appear to be installed. Please install and re-run this script."
  fi
}

download_terraform() {
  if [[ ! -e ${INSTALL_DIR}/terraform ]]; then
    mkdir -p ${INSTALL_DIR}
    curl -o "${TF_DOWNLOADED_FILE}" "${TF_DOWNLOAD_URL}"
    unzip "${TF_DOWNLOADED_FILE}" -d "${INSTALL_DIR}"
    rm "${TF_DOWNLOADED_FILE}"
  fi

  export TF="${INSTALL_DIR}/terraform"
}

download_packer() {
  if [[ ! -e ${INSTALL_DIR}/packer ]]; then
    # Download Packer
    mkdir -p ${INSTALL_DIR}
    curl -o "${PACKER_DOWNLOADED_FILE}" "${PACKER_DOWNLOAD_URL}"
    unzip "${PACKER_DOWNLOADED_FILE}" -d "${INSTALL_DIR}"

    rm "${PACKER_DOWNLOADED_FILE}"
  fi

  export PACKEREXE="${INSTALL_DIR}/packer"
}

##############################################
# Setup virtual environment and install python packages.
##############################################
setup_python() {
  echo "Setup Python"
  set +u
  VENV="${PWD}/.venv"
  VENV_BIN="${VENV}/bin"
  if [[ ! -n ${VIRTUAL_ENV} ]]; then
    if [[ ! -e ${VENV_BIN}/activate ]]; then
      virtualenv -q -p python3 --prompt="(packer-env) " ${VENV}
    fi

    source ${VENV_BIN}/activate

    pip install -q --upgrade pip
    pip install -q --upgrade setuptools
    # Pinning azure-mgmt-datalake-nspkg due to issue:
    # https://github.com/Azure/azure-sdk-for-python/issues/3512
    pip install -q azure-mgmt-datalake-nspkg\<3 azure-cli~=2.0
  fi

  set -u
  echo "Run: source .venv/bin/activate to activate environment"
}

check_env
download_packer
download_terraform
setup_python
export PATH=${PWD}/${INSTALL_DIR}:${PATH}
