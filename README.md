# Demo: deployment scripts for Quotes demo

## Github deployment

Run:

`tools\deploy.ps1 -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName`

The Web Apps will have the correct App Settings required for the applications. Manually link the Web Apps to Github repositories to deploy them (use Development Center of the Web Apps in the Azure Portal).

## Containers

### Deploy ARM template
Run:

`tools\deploy.ps1 -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -Template container-webapps`

### Or extend Github deployment
Add an Azure Container Registry (ACR) after creating the Resource Group for Github deployment. Compile as described below and then modify the Container Settings of the Web Apps to point to the new containers in the ACR.

### Compile
Full explanation:
https://docs.microsoft.com/en-us/azure/container-registry/container-registry-tutorial-quick-build

`set ACR_NAME=` Name of the ACR created above

`cd ..\Quotes.Web`

`az acr build --registry %ACR_NAME% --image quoteservice:v1 --file src\QuoteService\Dockerfile .`

`cd ..\Quotes.Service`

`az acr build --registry %ACR_NAME% --image quoteweb:v1 --file src\WebUI\Dockerfile .`


