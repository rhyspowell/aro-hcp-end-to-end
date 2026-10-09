# Azure resource location and subscription
LOCATION="eastus2"
SUBSCRIPTION_ID="$(az account show --query id --output tsv)"
CUSTOMER_RG_NAME="rhys-rg"
CLUSTER_NAME="rhys-hcp-aro"
MANAGED_RESOURCE_GROUP="${CLUSTER_NAME}-managed-rg"
NP_NAME="rhys-orig-np"
API_VERSION="2025-12-23-preview"

az rest \
  --method DELETE \
  --uri "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${CUSTOMER_RG_NAME}/providers/Microsoft.RedHatOpenShift/hcpOpenShiftClusters/${CLUSTER_NAME}?api-version=${API_VERSION}"

az rest \
  --method GET \
  --uri "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${CUSTOMER_RG_NAME}/providers/Microsoft.RedHatOpenShift/hcpOpenShiftClusters/${CLUSTER_NAME}?api-version=${API_VERSION}" \
  --query "properties.provisioningState" -o tsv

KV_NAME=$(az keyvault list --resource-group "$CUSTOMER_RG_NAME" --query "[0].name" -o tsv)
echo "Key Vault to purge after RG deletion: ${KV_NAME}"

az group delete --name "${CUSTOMER_RG_NAME}" --subscription "${SUBSCRIPTION_ID}" --location "${LOCATION}"

az keyvault purge --name "${KV_NAME}"


az ad app list --display-name "${APP_DISPLAY_NAME}" --query "[].appId" -o tsv
exit

az ad app delete --id "${CLIENT_ID}"

az group show --name "$CUSTOMER_RG_NAME" 2>/dev/null && echo "RG still exists" || echo "RG deleted"