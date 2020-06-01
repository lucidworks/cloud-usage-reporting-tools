#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null && pwd )"

SCRIPT_CMD="$0"
GCLOUD_PROJECT=
CLUSTER_NAME=
NAMESPACE=
OWNER_LABEL=
COST_CENTER=
PURPOSE=
END_DATE=

function print_usage() {
  CMD="$1"
  ERROR_MSG="$2"

  if [ "$ERROR_MSG" != "" ]; then
    echo -e "\nERROR: $ERROR_MSG" >&2
  fi

cat >&2 <<'EOF'

  -p                GCP project ID
  -c                GKE cluster name
  -n                Kubernetes namespace to label, or dash (-) to label cluster instead of a namespace
  --cost-center     Cost center for the namespace (NNN, or eng or sales or proserve or support (stored as NNNN))
  --purpose         Purpose, Salesforce customer or prospect name
  --end-date        Expected end date for the namespace (NN days from now or YYYY-mm-dd)
  --sfdc-oppid      Salesforce Opportunity ID
  -?,-help          Display this help
    -usage,
    --help,
    --usage

EOF
}


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
        -p)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -p parameter!"
              exit 1
            fi
            GCLOUD_PROJECT="$2"
            shift 2
        ;;
        -n)
            if [[ -z "$2" || ( "${2:0:1}" == "-" && "$2" != "-" )  ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -n parameter!"
              exit 1
            fi
            NAMESPACE="$2"
            shift 2
        ;;
        --cost-center)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --cost-center parameter!"
              exit 1
            fi
            COST_CENTER="$2"
            shift 2
        ;;
        --end-date)
            if [[ -h "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --end-date parameter!"
              exit 1
            fi
            END_DATE="$2"
            shift 2
        ;;
        --sfdc-oppid)
            if [[ -h "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --sfdc-oppid parameter!"
              exit 1
            fi
            SFDC_OPPID="$2"
            shift 2
        ;;
        --purpose)
            if [[ -h "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --purpose parameter!"
              exit 1
            fi
            PURPOSE="$2"
            shift 2
        ;;
        -help|-usage|--help|--usage|-?)
            print_usage "$SCRIPT_CMD"
            exit 0
        ;;
        --)
            shift
            break
        ;;
        *)
            if [[ "$1" != "" ]]; then
              print_usage "$SCRIPT_CMD" "Unrecognized or misplaced argument: $1!"
              exit 1
            else
              break # out-of-args, stop looping
            fi
        ;;
    esac
  done
fi

echo 'Checking environment and prerequisites...' >&2
gcloud --version > /dev/null 2<&1
has_prereq=$?
if [[ $has_prereq -eq 127 ]]; then
  echo -e "\nERROR: Must install GCloud command line tools! See https://cloud.google.com/sdk/docs/quickstarts" >&2
  exit 1
fi

# verify the user is logged in ...
who_am_i=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
if [[ -z "$who_am_i"  ]]; then
  echo -e "\nERROR: GCloud user unknown, please use: 'gcloud auth login <account>' before proceeding with this script!" >&2
  exit 1
fi

echo -e "Logged in as: $who_am_i" >&2
OWNER_LABEL="${who_am_i//[^a-zA-Z0-9\.\_\-]/-}"
OWNER_LABEL="${OWNER_LABEL//\./_}"
OWNER_LABEL="${OWNER_LABEL:0:63}"
OWNER_LABEL="${OWNER_LABEL/%[^A-Za-z0-9]/0}"

hash kubectl
has_prereq=$?
if [[ $has_prereq -eq 1 ]]; then
  echo -e "\nERROR: Must install kubectl before proceeding with this script! For GKE, see: https://cloud.google.com/sdk/docs/" >&2
  exit 1
fi


while [[ -z "${GCLOUD_PROJECT}" ]]; do
  gcloudprojects=$(gcloud projects list --filter 'lifecycleState:ACTIVE' --format 'value(projectId)' --sort-by projectId)
  if [[ -n "$gcloudprojects" ]] ; then
    PS3="Enter the number of the GCP project, or type a GCP project ID: "
    select GCLOUD_PROJECT in $gcloudprojects; do
      if [[ -z "${GCLOUD_PROJECT}" ]]; then GCLOUD_PROJECT="${REPLY}"; fi
      break
    done
  else
    read -p "Enter a GCP project ID: " GCLOUD_PROJECT
  fi
done
GCLOUD_PROJECT=${GCLOUD_PROJECT//[^a-zA-Z0-9\-]/-}
echo "Using GCP project ID [${GCLOUD_PROJECT}]" >&2
GCLOUD_PROJECT=$(gcloud projects describe "${GCLOUD_PROJECT}" --format 'value(projectId)')
has_project=$?
if [ $has_project -ne 0 ] ; then 
  echo -e "\nERROR: Project [${GCLOUD_PROJECT}] not found" >&2
  exit $has_project
fi


while [[ -z "${CLUSTER_NAME}" ]]; do
  clusternames=$(gcloud container clusters list --project "${GCLOUD_PROJECT}" --format 'value(name)' --sort-by name)
  if [[ -n "$clusternames" ]]; then
    PS3="Enter the number of the GKE cluster, or type a GKE cluster name: "
    select CLUSTER_NAME in $clusternames; do
      if [[ -z "${CLUSTER_NAME}" ]]; then CLUSTER_NAME="${REPLY}"; fi
      break
    done
  else
    read -p "Enter a GKE cluster name: " CLUSTER_NAME
  fi
done
CLUSTER_NAME=${CLUSTER_NAME//[^a-zA-Z0-9\-]/-}
echo "Using GKE cluster name [${CLUSTER_NAME}]" >&2
clust_loc=($(gcloud container clusters list --project "${GCLOUD_PROJECT}" --filter "name=${CLUSTER_NAME}" --format "value(name,location)" --limit 1))
has_cluster=$?
if [[ -z "${clust_loc[0]}" || $has_cluster -ne 0 ]]; then
  echo -e "\nERROR: Cluster [${CLUSTER_NAME}] not found in project" >&2
  exit $(($has_cluster>0?$has_cluster:1))
fi
CLUSTER_NAME=${clust_loc[0]}
location=${clust_loc[1]}
echo "Found [${CLUSTER_NAME}] in location [${location}]" >&2



export KUBECONFIG="$(mktemp)"
trap "rm -rf ${KUBECONFIG}" EXIT
gcloud container clusters get-credentials "${CLUSTER_NAME}" --project "${GCLOUD_PROJECT}" --region "${location}" 2> /dev/null
while [[ -z "${NAMESPACE}" ]]; do
  namespaces=$(kubectl get ns -o jsonpath='{$.items[*].metadata.name}')
  if [[ -n "$namespaces" ]]; then
    PS3="Enter the number of the Kubernetes namespace, or type a namespace name, or dash (-) for no namespace: "
    select NAMESPACE in $namespaces "-"; do
      if [[ -z "${NAMESPACE}" ]]; then NAMESPACE="${REPLY}"; fi
      break
    done
  else
    read -p "Enter a Kubernetes namespace name, or dash (-) for no namespace: " NAMESPACE
  fi
done
NAMESPACE=${NAMESPACE//[^a-zA-Z0-9\-]/-}
if [[ "${NAMESPACE}" != "-" ]]; then
  echo "Using Kubernetes namespace [${NAMESPACE}]" >&2
  ns=($(kubectl get ns --field-selector "metadata.name=${NAMESPACE}" -o jsonpath="{$.items[*].metadata.name}"))
  NAMESPACE=${ns[0]}
  if [[ -z "${NAMESPACE}" ]] ; then
    echo -e "\nERROR: Namespace [${NAMESPACE}] not found in cluster" >&2
    exit 1
  fi
fi


 
costcenters=(
  110_ga
  120_fa
  130_hr
  140_it
  150_facilities
  160_digitalcommerce
  210_development
  220_datascience
  230_solutionsengineering
  240_product
  260_docs
  270_mserv
  500_sales
  510_salesmgmt
  520_fieldsales
  530_insidesales
  540_channelsales
  550_salesengineering
  560_customersuccess
  410_corporatemarketing
  420_demandmarketing
  310_professionalservices
  320_training
  330_support
  340_cor
)

while [[ -z "${COST_CENTER}" ]]; do
  PS3="Enter the number corresponding to your cost center: "
  select COST_CENTER in "${costcenters[@]}" ; do
    if [[ -n "${COST_CENTER}" ]]; then
      break
    fi
  done
done
has_costcenter=
for i in ${costcenters[@]} ; do 
  if [[ "${i}" == "${COST_CENTER}"* ]]; then has_costcenter="${i}" ; fi
done
if [[ -n "$has_costcenter" ]] ; then
  COST_CENTER="$has_costcenter"
else
  echo -e "\nERROR: Invalid cost center [${COST_CENTER}]" >&2
  exit 1
fi


while [[ -z "${PURPOSE}" ]]; do
  read -p "Provide a purpose, customer, or prospect name (as required by department policy): " PURPOSE
done
PURPOSE="${PURPOSE//[^a-zA-Z0-9\-\.\_]/-}"
PURPOSE="${PURPOSE//\./_}"
PURPOSE="${PURPOSE:0:63}"
PURPOSE="${PURPOSE/#[^A-Za-z0-9]/0}"
PURPOSE="${PURPOSE/%[^A-Za-z0-9]/0}"

echo >&2
echo "Label owner: [${OWNER_LABEL}]"
echo "Label cost-center: [${COST_CENTER}]" >&2
echo "Label purpose: [${PURPOSE}]" >&2


if [[ "${NAMESPACE}" == "-" ]]; then
  gcloud container clusters update "${CLUSTER_NAME}" --update-labels "owner=${OWNER_LABEL//\./_},cost-center=${COST_CENTER},purpose=${PURPOSE//\./_}"
  kubectl label --overwrite ns "kube-system" "owner=${OWNER_LABEL}" "cost-center=${COST_CENTER}" "purpose=${PURPOSE}" -o jsonpathy='{.}'
else
  kubectl label --overwrite ns "${NAMESPACE}" "owner=${OWNER_LABEL}" "cost-center=${COST_CENTER}" "purpose=${PURPOSE}" -o jsonpath='{.}'
fi


if [[ "${COST_CENTER}" == 5??_* || "${COST_CENTER}" == 310_* ]] ; then
  
  while true ; do
    if [[ -z "${END_DATE}" ]]; then
      read -p "Enter expected end date as days from today as NN, or as YYYY-mm-dd (e.g. 10 or 1977-05-25): " END_DATE
    fi
    if [[ "${END_DATE}" =~ ^[[:digit:]]{4}-[[:digit:]]{1,2}-[[:digit:]]{1,2}$ ]]; then
      case ${OSTYPE} in
        linux-gnu) 
          endiso=$(date -d "${END_DATE}" '+%Y-%m-%d') && endepoch=$(date -d "${END_DATE}" '+%s') && nowepoch=$(date '+%s') || END_DATE=
          ;;
        darwin*)
          endiso=$(date -j -f '%Y-%m-%d' "${END_DATE}" '+%Y-%m-%d') && endepoch=$(date -j -f '%Y-%m-%d' "${END_DATE}" '+%s') && nowepoch=$(date -j '+%s') || END_DATE=
          ;;
        *) echo -e "\nERROR: ${OSTYPE} not supported" >&2 ; exit 1 ;;
      esac
      let daysdiff="( $endepoch - $nowepoch ) / 86400"
    elif [[ "${END_DATE}" =~ ^\+?[[:digit:]]+$ ]]; then
      let daysdiff="${END_DATE}" || { echo "Invalid end date specification [${END_DATE}]" >&2 ; END_DATE= ; }
      case ${OSTYPE} in
        linux-gnu) 
          endiso=$(date -d "now+${daysdiff}days" '+%Y-%m-%d')
          ;;
        darwin*)
          endiso=$(date -j "-v+${daysdiff}d" '+%Y-%m-%d')
          ;;
        *) echo -e "\nERROR: ${OSTYPE} not supported" >&2 ; exit 1 ;;
      esac
    else
      echo "Invalid end date specification [${END_DATE}]"
      END_DATE=
    fi

    if [[ "${COST_CENTER}" == 5??_* && $daysdiff -gt 30 ]]; then
      echo -e "\nERROR: [Ending date ${END_DATE}] is ${daysdiff} days from today, which is above the allowed maximum" >&2
      END_DATE=
    fi

    if [[ -n "${END_DATE}" ]] ; then break ; fi
  done
  END_DATE=$endiso
  echo "Label end-date: [${END_DATE}] (${daysdiff} days from today)" >&2

  if [[ "${NAMESPACE}" == "-" ]]; then
    gcloud container clusters update "${CLUSTER_NAME}" --update-labels "end-date=${END_DATE}"
    kubectl label --overwrite ns "kube-system" "end-date=${END_DATE}" -o jsonpathy='{.}'
  else
    kubectl label --overwrite ns "${NAMESPACE}" "end-date=${END_DATE}" -o jsonpath='{.}'
  fi

fi

