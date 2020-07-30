#!/bin/bash

#############################################
# Because BASH does not have a die function #
#   we must provide one                     #
#############################################
function die
{
    local message=$1
    [ -z "$message" ] && message="Died"
    echo "${BASH_SOURCE[1]}: line ${BASH_LINENO[0]}: ${FUNCNAME[1]}: $message." >&2
    exit 1
}

#####################
# Process arguments #
#####################
usage() {
    echo "Usage: $0 -k </full/path/to/private_deploy_key>" 1>&2
    exit 1
}

while getopts 'hk:' OPTION; do
  case "$OPTION" in
    k)
      DEPLOY_KEY="$OPTARG"
      [[ -f $DEPLOY_KEY && -s $DEPLOY_KEY ]] || die "The deployment private key $DEPLOY_KEY does not exist or is empty"
      ;;
    h)
      usage
      ;;
    ?)
      usage
      ;;
  esac
done
shift "$(($OPTIND -1))"

[[ -n ${DEPLOY_KEY+x} ]] || die "You must supply a private key"  

############################
#     Determine if we      #
# have a valid environment #
############################
need() {
    which "$1" &>/dev/null || die "Binary '$1' is missing but required"
}

need "kubectl"
need "helm"
need "vault"
need "sed"
need "jq"
need "git"

###########################
# Generic output function #
###########################
message() {
  echo -e "\n######################################################################"
  echo "# $1"
  echo "######################################################################"
}

#####################################
# Bootstrap the Flux deployment key #
#####################################
setupFluxKey() {
  message "Setting key for Flux"
  kubectl create -f "$REPO_ROOT/flux/namespace.yaml"
  kubectl create secret generic flux-git-deploy --namespace flux --from-file=identity=$DEPLOY_KEY
}

################
# Install Flux #
################
installFlux() {
  message "installing flux"
  # install flux
  helm repo add fluxcd https://charts.fluxcd.io
  kubectl apply -f https://raw.githubusercontent.com/fluxcd/helm-operator/master/deploy/crds.yaml
  helm upgrade --install flux --values "$REPO_ROOT"/flux/flux/flux-values.yaml --namespace flux fluxcd/flux
  helm upgrade --install helm-operator --values "$REPO_ROOT"/flux/helm-operator/flux-helm-operator-values.yaml --skip-crds --namespace flux fluxcd/helm-operator

  FLUX_READY=1
  while [ $FLUX_READY != 0 ]; do
    echo "waiting for flux pod to be fully ready..."
    kubectl -n flux wait --for condition=available deployment/flux
    FLUX_READY="$?"
    sleep 5
  done

  # grab output the key
  FLUX_KEY=$(kubectl -n flux logs deployment/flux | grep identity.pub | cut -d '"' -f2)

  # This may be useful if we can get ADO repo key addition some day. Commenting out for now.
  #message "adding the key to github automatically"
  #"$REPO_ROOT"/setup/add-repo-key.sh "$FLUX_KEY"
}

#################
# Main function #
#################
# Find the root for the script path
REPO_ROOT=$(git rev-parse --show-toplevel)

# Setup Flux deployment key
setupFluxKey

# Install Flux
installFlux

# setup static objects
#"$REPO_ROOT"/setup/bootstrap-objects.sh

# initialize the Vault
#"$REPO_ROOT"/setup/bootstrap-vault.sh

message "all done!"
#kubectl get nodes -o=wide

# finished
