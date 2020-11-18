#!/bin/bash
set -xeou pipefail

readonly TERRAFORM_VERSION="0.11.3"
readonly DOWNLOAD_FILE="${WORKSPACE}/tmp/terraform_${TERRAFORM_VERSION}.zip"
readonly DOWNLOAD_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
readonly INSTALL_DIR="${WORKSPACE}/bin"
readonly TF="${INSTALL_DIR}/terraform"
readonly VENV="${INSTALL_DIR}/venv"

dry_run=false
workers=
job_id=
action=
region=


function setup() {
  setup_terraform
  setup_azurecli
}

function setup_azurecli() {
  if [[ ! -e ${VENV}/bin/python ]]; then
    virtualenv -q -p python3 ${VENV}

    ${VENV}/bin/pip install -q --upgrade pip setuptools
    # Pinning azure-mgmt-datalake-nspkg due to issue:
    # https://github.com/Azure/azure-sdk-for-python/issues/3512
    ${VENV}/bin/pip install -q azure-mgmt-datalake-nspkg\<3 azure-cli~=2.0
  fi
  # We want to allow this script to do as it pleases I dont have
  # Control of unbound variables here
  set +u
  source ${VENV}/bin/activate
  set -u

  set +x
  echo "Authenticating to azure cli"
  az login --service-principal -u ${ARM_CLIENT_ID} -p ${ARM_CLIENT_SECRET} --tenant ${ARM_TENANT_ID}
  az account set --subscription="${ARM_SUBSCRIPTION_ID}"
  set -x
}

function setup_terraform() {
  mkdir -p ${WORKSPACE}/tmp
  mkdir -p ${WORKSPACE}/bin
  if [ -f ${TF} ]; then
    if [ "$(${TF} version | grep -c ${TERRAFORM_VERSION})" -eq "1" ]; then
      return
    else
      rm ${TF}
    fi
  fi
    curl -o ${DOWNLOAD_FILE} ${DOWNLOAD_URL}
    unzip ${DOWNLOAD_FILE} -d ${INSTALL_DIR}
    rm ${DOWNLOAD_FILE}
}

function print_help() {
  cat <<eof
Usage: provision.sh [OPTIONS]

Options:
  -a:       (REQUIRED) sets the action of the script, either "provision" or "decommision"
  -d:       (OPTIONAL) sets the process to be a dry run, no resources will be created or destroyed

Provision Options:
  -j:       (REQUIRED) sets the job id for the given process
  -w:       (REQUIRED) sets the amount of workers required for a given job
  -r:       (REQUIRED) sets the region of the job
eof
}

function decommission() {
  pushd ${WORKSPACE}/tmp
  tar xzf tf_files.tar.gz
  popd

  pushd ${WORKSPACE}/tmp/tf_files
  ${TF} init -input=false

  if [ ${dry_run} = false ]; then
    ${TF} destroy -force
  else
    ${TF} plan -destroy -input=false
  fi

  popd
}

function provision() {
  local run_id=$1
  local slave_count=$2
  local region=$3
  local dry_run=$4

  mkdir -p ${WORKSPACE}/tmp/tf_files && rsync -av --copy-links ${WORKSPACE}/terraform/jmeter/ ${WORKSPACE}/tmp/tf_files
  pushd ${WORKSPACE}/tmp/tf_files

  echo 'run_id = "'${run_id}'"' >> ${run_id}.auto.tfvars
  echo 'slave_count = "'${slave_count}'"' >> ${run_id}.auto.tfvars
  echo 'region = "'${region}'"' >> ${run_id}.auto.tfvars

  ${TF} init -input=false
  if [ ${dry_run} = false ]; then
    ${TF} apply -input=false -auto-approve
  else
    ${TF} plan -input=false
  fi

  popd

  pushd ${WORKSPACE}/tmp
  tar czf tf_files.tar.gz tf_files
  popd
}

while getopts "a:j:w:r:d" opt; do
  case $opt in
    a)
      action="$OPTARG"
      ;;
    j)
      job_id="$OPTARG"
      ;;
    w)
      workers="$OPTARG"
      ;;
    r)
      region="$OPTARG"
      ;;
    d)
      dry_run=true
      ;;
  esac
done

if [ -z ${action} ]; then
  echo "Action must be specified!" >&2
  print_help
  exit 1
fi


setup
if [ "$action" = "provision" ]; then

  if [ -z ${workers} ]; then
    echo "Workers must be specified!" >&2
    print_help
    exit 1
  fi

  if [ -z ${job_id} ]; then
    echo "Job ID must be specified!" >&2
    print_help
    exit 1
  fi

  if [ -z ${region} ]; then
    echo "Region must be specified!" >&2
    print_help
    exit 1
  fi

  provision $job_id $workers $region $dry_run
elif [ "$action" = "decommission" ]; then
  decommission
else
  exit 0
fi

