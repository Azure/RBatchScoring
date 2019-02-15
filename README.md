# Batch forecasting on Azure with R models

## Overview

In this repository, we use the scenario of product sales forecasting to demonstrate the recommended approach for batch scoring with R models on Azure. This architecture can be generalized for any scenario involving batch scoring using R models.

## Design
![Reference Architecture Diagram](https://happypathspublic.blob.core.windows.net/assets/batch_forecasting/images/architecture.png)

The above architecture works as follows:
1. Model scoring is parallelized across a cluster of virtual machines running on Azure Batch.
2. Each Batch job reads input data from a Blob container, makes a prediction using pre-trained R models, and writes the results back to the Blob container.
3. Batch jobs are triggered by a scheduler script using the doAzureParallel R package. The script runs on an Azure Container Instance (ACI).
4. The ACI is run on a schedule managed by a Logic App.

## Forecasting scenario

This example uses the scenario of a large food retail company that needs to forecast the sales of thousands of products across multiple stores. A large grocery store can carry tens of thousands of products and generating forecasts for so many product/store combinations can be a very computationally intensive task. In this example, we generate forecasts for 1,000 products across 83 stores, resuling in 5.4 million scoring operations. The architecture deployed is capable of scaling to this challenge. See [here](./forecasting_scenario.md) for more details of the forecasting scenario.

![Product sales forecasting](https://happypathspublic.blob.core.windows.net/assets/batch_forecasting/images/forecasts.png)

## Prerequisites

This repository has been tested on an [Ubuntu Data Science Virtual Machine](https://azuremarketplace.microsoft.com/marketplace/apps/microsoft-dsvm.linux-data-science-vm-ubuntu) which comes with manay of the local/working machine dependencies pre-installed.

Local/Working Machine:
- Ubuntu >=16.04LTS (not tested on Mac or Windows)
- R >= 3.4.3
- [Docker](https://docs.docker.com/install/linux/docker-ce/ubuntu/#install-docker-ce-1)  >=1.0
- [Azure CLI](https://docs.microsoft.com/cli/azure/?view=azure-cli-latest) >=2.0

R packages*:
- gbm >=2.1.4.9000
- rAzureBatch >=0.6.2
- doAzureParallel >=0.7.2
- bayesm >=3.1-1
- ggplot2 >= 3.1.0
- tidyr >=0.8.2
- dplyr >=0.7.8
- jsonlite >=1.5
- devtools >=1.13.4
- dotenv >=1.0.2
- AzureStor >=1.0.0
- AzureRMR >=1.0.0

\* Install all R package dependencies by running `Rscript R/install_dependencies.R`

Accounts:
- [Azure Subscription](https://azure.microsoft.com/free/)
- [Dockerhub account](https://hub.docker.com/)

While it is not required, [Azure Storage Explorer](https://azure.microsoft.com/features/storage-explorer/) is useful to inspect your storage account.

## Setup

1. Clone the repo `git clone <repo-name>`
2. `cd` into the repo
3. Install R dependencies `Rscript R/install_dependencies.R`
4. Log in to Azure using the Azure CLI `az login`
7. Log in to Docker `docker login`
8. Enable non-root users to run docker commands
    ```
    sudo groupadd docker
    sudo usermod -aG docker $USER
    ```
    Restart your terminal after running the above commands

## Deployment steps

Run through the following R scripts. It is intended that you step through each script interactively using an IDE such as RStudio. Before executing the scripts, set your working directory of your R session `setwd("~/RBatchScoring")`. It is recommended that you restart your R session and clear the R environment before running each script.
1. [01_generate_forecasts_locally.R](./01_generate_forecasts_locally.R)
2. [02_deploy_azure_resources.R](./02_deploy_azure_resources.R)
3. [03_(optional)_train_forecasting_models.R](./03_(optional)_train_forecasting_models.R)
4. [04_forecast_on_batch.R](./04_forecast_on_batch.R)
5. [05_run_from_docker.R](./05_run_from_docker.R)
6. [06_deploy_logic_app.R](./06_deploy_logic_app.R) \*

\* Note: after running the 06_deploy_logic_app.R script, you will need to authenticate to allow the Logic App to create an ACI. Go into the Azure portal and open up the ACI connector to authenticate as shown below.
![ACI connector authentication](https://happypathspublic.blob.core.windows.net/assets/batch_scoring_for_dl/azure_aci_connector_auth.PNG)

# Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.microsoft.com.

When you submit a pull request, a CLA-bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., label, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.