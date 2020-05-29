# Lucidworks GKE cluster/namespace label helper

A script to help you make sure your clusters and namespaces are labeled in accordance with policies and requirements.

This script may be updated at times to reflect rule changes, to fix bugs, or for general improvements. It may be easiest to stay up-to-date by pulling it from the `git` repository.

## Description

Run the shell script `./gke_label.sh`

If you provide no arguments, the script will interactively prompt you to provide information

You can provide all required information to run the script non-interactively, e.g.

    ./gke_label.sh -p lw-sales -c lw-sales-us-west1 -n gk-x-demo --cost-center 550 --purpose "Customer X" --end-date +10
    
If you omit required parameters, the script will interactively prompt you for any missing ones.

In all cases, the script will provide feedback on parameters to stdout

## Parameters

```
  -p                GCP project ID
  -c                GKE cluster name
  -n                Kubernetes namespace to label, or dash (-) to label cluster instead of a namespace
  --cost-center     Cost center for the namespace (NNN, or eng or sales or proserve or support (stored as NNNN))
  --purpose         Purpose, Salesforce customer or prospect name
  --end-date        Expected end date for the namespace (YYYY-MM-DD or +NN in days)
  --sfdc-oppid      Salesforce Opportunity ID
  -?,-help          Display this help
    -usage,
    --help,
    --usage

```

## Requirements
* `/bin/bash` must be available
* The `gcloud` command-line tools must be installed and available (https://cloud.google.com/sdk/)
* You must be logged in to `gcloud` as a user with permissons to label the GKE cluster or k8s namespace (`gcloud auth login` or `gcloud init`)
* The `kubectl` command-line tool must be installed and available (`glcoud components install kubectl` or https://kubernetes.io/docs/tasks/tools/install-kubectl/)
* Only Linux (including WSL) and MacOS are fully supported; other platforms with `bash` may partially work
