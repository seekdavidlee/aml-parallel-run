# Introduction

This repo is to demonstrate running jobs privately in AML. It contains the infra code to setup Azure Machine Learning (AML) dependencies as private resources and run AML jobs in a private environment. It contains a setup script which you can use to run AML jobs in parallel. 

There are 2 seperate components of AML, the AML workspace and AML Compute. We can think of AML workspace as managing AML dependencies such as setting up Datasources, Computes, etc. When we are actually running pipeline jobs, those jobs are running as AML Compute and in our case, as Compute Clusters. In this repo, we are only ensuring the job is running privately, not the AML workspace.

## Setup Notes

* There are 4 subnets created, only the `resources` and `amlcompute` subnets are used in this demo.
* The `resources` subnet contains the private endpoints for Azure Container Registry, Azure Storage, and Azure Key Vault.
* The `amlcompute` subnet is used to host the AML Compute Cluster where VMs will be created and will have access to `resources` subnet to access the privae endpoints.
* Because your Azure resources have private endpoints, as a user, you would normally want to connect to a VNET in order to access those resources. However this would require additional network setup such as a point-to-site VPN. For the purpose of this demo, your IP is simply added to the firewall.
* Most setup work are done in the `aml.bicep` script. However, there are some setup that is done after all resources have been provisioned. This is done as part of the `Setup.ps1` script. You can reference these scripts for the setup details.

## Prerequisites

* You must have rights to perform role assignments. 
* Login to your Azure Subscription via Azure CLI.

## Setup AML Environment

The `-prefix` parameter is where you would supply a globally unqiue name. This is how your Azure resources will be named.

```powershell
.\Setup.ps1 -prefix <YOUR_PREFIX>
```

When this is completed, you will also noticed an environment `.env` file created. There are no secrets here. It contains the details for us to kick off a job. 

## Python Setup

Navigate to the src directory and follow the steps below:

Activate virtual environment

```bash
venv\Scripts\activate
```

Install python dependencies.

```bash
pip install -r requirements.txt
```

## Stage test data

This script will create some test data for the AML parallel job to use.

```bash
python .\upload_data.py
```

## Run a Job

To run an job, you can use the `run` python script. It uses the `.env` file created in a previous step to run. It will schedule a pipeline to be executed in Azure Machine Learning.

```bash
python .\run.py
```

A link will be present at the end. Click on the link to navigate to your job. You can change the `.env` parameters. For example you may consider upping the `AML_JOB_CONCURRENCY` to 2 and running again.

## Take away

* Consider refactoring the `src/run.py` script as starting point to create your own pipeline job.
* Consider refactoring the `src/code/run_job.py` as a starting point to process your files.