# Batch forecasting on Azure with R models

## Overview

In this repository, we use the scenario of product sales forecasting. This architecture can be generalized for any scenario involving batch scoring using R models.

## Design
![Reference Architecture Diagram](https://happypathspublic.blob.core.windows.net/assets/batch_forecasting/images/architecture.png)

The above architecture works as follows:
1. A Logic App triggers an Azure Container Instance (ACI) on a schedule
2. The ACI uses the doAzureParallel R package to create multiple jobs running on an Azure Batch cluster
3. Each job reads input data from from a File Share mounted on each node of the cluster and generates a forecast using pre-trained R models
4. The forecast results are then written back to the File Share

### Forecasting scenario
![Product sales forecasting](https://happypathspublic.blob.core.windows.net/assets/batch_forecasting/images/forecasts.png)

This example uses the scenario of a large food retail company that needs to forecast the sales of thousands of products across multiple stores. A large grocery store can typically carry many tens of thousands of products and generating forecasts for so many product/store combinations can be a very computationally intensive task. This example uses the Orange Juice dataset from the *bayesm* R package which consists of just over two year's worth of weekly sales data for 11 orange juice brands across 83 stores. The data includes covariates including the prices of each product, whether the product was on a deal or was featured in the store in each week. We expand this data through replication, resulting in 1000 products across 83 stores. We use show how trained GBM models (from the *gbm* R package) can be used to generate quantile forecasts with a forecast horizon of 13 weeks (1 quarter). Quantile forecasts allow for the uncertainty in the forecast to be estimanted and in this example we generate five quantiles (the 5th, 25th, 50th, 75th and 95th quantiles). The total number of model scoring operations is 1000 products x 83 stores x 13 weeks x 5 quantiles = 5.4 million. A large retail store could carry many times this number of products but this architecture is capable of scaling to this challenge.

## Prerequisites

Local/Working Machine:
- Ubuntu >=16.04LTS (not tested on Mac or Windows)
- R >= 3.4.3
- [Docker >=1.0](https://docs.docker.com/install/linux/docker-ce/ubuntu/#install-docker-ce-1)
- [AzCopy >=7.0.0](https://docs.microsoft.com/azure/storage/common/storage-use-azcopy-linux?toc=%2fazure%2fstorage%2ffiles%2ftoc.json)
- [Azure CLI >=2.0](https://docs.microsoft.com/en-us/cli/azure/?view=azure-cli-latest)

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
- [Dockerhub account](https://hub.docker.com/)
- [Azure Subscription](https://azure.microsoft.com/free/)

While it is not required, it is also useful to use the [Azure Storage Explorer](https://azure.microsoft.com/features/storage-explorer/) to inspect your storage account. Alternatively, you can mount the File Share to your local machine.

## Setup

1. Clone the repo `git clone <repo-name>`
2. `cd` into the repo
3. Install R dependencies `Rscript R/install_dependencies.R`
4. Log in to Azure using the Azure CLI `az login`
5. Setup resources for doAzureParallel using service principal. You will be asked to provide names for several resources.
    ```
    wget -q https://raw.githubusercontent.com/Azure/doAzureParallel/master/account_setup.sh &&
    chmod 755 account_setup.sh &&
    /bin/bash account_setup.sh serviceprincipal
    ```

    Note: you **must** copy the output of the above command into *azure/credentials.json*.
6. Log in to Docker using the docker cli `docker login`

## Steps:

Run through the following R scripts (ideally from R Studio):
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