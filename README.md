
## Prerequisites

- Ubuntu 16.04
- Docker
- R*
- RStudio*
- Python 3*
- Azure CLI*

\* These prerequisites are all included in the docker image

## Setup

1. Clone the repository `git clone`
2. `cd` into repo directory
3. Pull the docker image
    ```bash
    docker pull
    ```
4. Get the data
    ```bash
    docker run --rm -v $(pwd):/rbatch rbatch /bin/bash -c 'cd rbatch; Rscript R/get_data.R' --rm
    ```
5. Complete the doAzureParallel [setup instructions](https://github.com/Azure/doAzureParallel#setup), making a note of your resource names in [template.env](./template.env). Copy and save the credentials from the setup script in [credentials.json](./credentials.json).

    Note: you can set up doAzureParallel with shared access key or Azure Active Directory authentication (see [here](https://github.com/Azure/doAzureParallel/blob/master/docs/02-getting-started-script.md))
6. Finish filling out template.env, copy to new file and load
    ```
    cp template.env .env
    source .env
    ```

## Generate forecasts locally
1. Start an RStudio session in the docker container
    ```bash
    docker run -v $(pwd):/rbatch -d -p 8787:8787 -e PASSWORD=<password> --name rbatch angusrtaylor/rbatch /init
    ```


## Generate forecasts with doAzureParallel
1. Start an interative docker container
    ```
    docker run -it --rm -v $(pwd):/rbatch --entrypoint /bin/bash rbatch
    cd rbatch
    ``` 
2. Login to Azure
    ```
    az login
    ```
3. Select your subscription
    ```
    az account list -o table
    az account set -s <subscription-id>
4. Create an Azure File Share and upload the data
    ```
    RBATCH_SA_KEY=$(az storage account keys list -g $RBATCH_RG --account-name $RBATCH_SA --query "[0].value" | tr -d '"')
    az storage share create -n $RBATCH_SHARE --account-name $RBATCH_SA
    az storage file upload --account-name $RBATCH_SA --account-key $RBATCH_SA_KEY --share-name $RBATCH_SHARE --source "./data/data.csv" --path "data.csv"
    ```
5. Create the cluster config file
    ```
    Rscript R/create_cluster_config.R --clust $RBATCH_CLUST --sa $RBATCH_SA --sakey $RBATCH_SA_KEY --share $RBATCH_SHARE
    ```

## Generate forecasts using doAzureParallel



## Using your own docker image

You can customize your docker image

```

```
    ```
8. 