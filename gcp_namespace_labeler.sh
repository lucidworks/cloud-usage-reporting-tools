#!/bin/bash
#Script for labling namespaces

GCLOUD_PROJECT=
GCLOUD_CLUSTER=
NAMESPACE=
COSTCENTER_TAG=


echo "Use this script for adding the required tags to your namespace"


#Usage function for --help --usage
function print_usage() {
  CMD="$1"
  ERROR_MSG="$2"

  if [ "$ERROR_MSG" != "" ]; then
    echo -e "\nERROR: $ERROR_MSG\n"
  fi

  echo -e "  -c              Name of the GKE cluster (required)\n"
  echo -e "  -n              Kubernetes namespace (required)\n"
  echo -e "  -p              GCP Project ID (required)\n"

}


#Entry parameters
if [ $# -gt 0 ]; then
  while true; do
    case "$1" in
        -c)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -c parameter!"
              exit 1
            fi
            CLUSTER_NAME="$2"
            shift 2
        ;;
        -n)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -n parameter!"
              exit 1
            fi
            NAMESPACE="$2"
            shift 2
        ;;
        -p)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -p parameter!"
              exit 1
            fi
            GCLOUD_PROJECT="$2"
            shift 2
        ;;
        -help|-usage|--help|--usage)
            print_usage "$SCRIPT_CMD"
            exit 0
        ;;
        *)
            if [ "$1" != "" ]; then
              print_usage "$SCRIPT_CMD" "Unrecognized or misplaced argument: $1!"
              exit 1
            else
              break # out-of-args, stop looping
            fi
        ;;
    esac
  done
fi


if [ "$CLUSTER_NAME" == "" ]; then
  print_usage "$SCRIPT_CMD" "Please provide the GKE cluster name using: -c <cluster>"
  exit 1
fi

if [ "$NAMESPACE" == "" ]; then
  print_usage "$SCRIPT_CMD" "Please provide the namespace name using: -n <namespace>"
  exit 1
fi


if [ "$GCLOUD_PROJECT" == "" ]; then
  print_usage "$SCRIPT_CMD" "Please provide the GCP project name using: -p <project>"
  exit 1
fi



gcloud --version > /dev/null 2<&1
has_prereq=$?
if [ $has_prereq == 1 ]; then
  echo -e "\nERROR: Must install GCloud command line tools! See https://cloud.google.com/sdk/docs/quickstarts"
  exit 1
fi

# verify the user is logged in ...
who_am_i=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
if [ "$who_am_i" == "" ]; then
  echo -e "\nERROR: GCloud user unknown, please use: 'gcloud auth login <account>' before proceeding with this script!"
  exit 1
fi

OWNER_LABEL="${who_am_i//@/-}"
echo -e "\nLogged in as: $who_am_i\n"

hash kubectl
has_prereq=$?
if [ $has_prereq == 1 ]; then
  echo -e "\nERROR: Must install kubectl before proceeding with this script! For GKE, see: https://cloud.google.com/sdk/docs/"
  exit 1
fi


current_value=$(gcloud config get-value project)
if [ "${current_value}" != "${GCLOUD_PROJECT}" ]; then
  gcloud config set project "${GCLOUD_PROJECT}"
fi


#Select for costcenter tag, you can use multiple selects for predefined values for tags
#Tags only admin letters, numbers, underscores and hiphens

PS3='Please enter the number corresponding to the costcenter tag to apply:'
costtag=("sales" "engineering" "proserve" "support")
select opt in "${costtag[@]}"
do
    case $opt in
        "sales")
            COSTCENTER_TAG="sales"
            break
            ;;
        "engineering")
            COSTCENTER_TAG="engineering"
            break
            ;;
        "proserve")
            COSTCENTER_TAG="proserve"
            break
            ;;
        "support")
            COSTCENTER_TAG="support"
            break
            ;;
        *)
            break
        ;;
    esac
done

#Optional labels
echo "The following are optional tags, press enter in case you don't need them:"
echo "End date for your namespace (mm-dd-yyyy):"
read END_DATE
echo "Opportunity ID:"
read OPPORTUNITY_ID
echo "Account name (Within SFDC):"
read ACCOUNT_NAME


#Adding the labels, we overwrite them to allow multiple executions
kubectl label --overwrite namespace "${NAMESPACE}" owner="${OWNER_LABEL}" costcenter="${COSTCENTER_TAG}" opportunityID="${OPPORTUNITY_ID}" accountName="${ACCOUNT_NAME}" endDate="${END_DATE}"


#Just for checking the applied labels
kubectl get namespace "${NAMESPACE}" --show-labels
