# Azure resource location and subscription
LOCATION="eastus2"
SUBSCRIPTION_ID="$(az account show --query id --output tsv)"

CUSTOMER_RG_NAME="rhys-rg"

# Network resources
CUSTOMER_NSG="rhys-nsg"
CUSTOMER_VNET_NAME="rhys-vnet"
CUSTOMER_VNET_SUBNET1="rhys-worker-subnet"
CUSTOMER_VNET_INTEGRATION_SUBNET_NAME="rhys-peer-subnet"

# Cluster and node pool
CLUSTER_NAME="rhys-hcp-aro"
MANAGED_RESOURCE_GROUP="${CLUSTER_NAME}-managed-rg"
NP_NAME="rhys-orig-np"
API_VERSION="2025-12-23-preview"
CLUSTER_VERSION="4.22"    # Example: 4.20
NP_VERSION="4.22.5"   # Example: 4.20.8

az rest \
  --method POST \
  --uri "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${CUSTOMER_RG_NAME}/providers/Microsoft.RedHatOpenShift/hcpOpenShiftClusters/${CLUSTER_NAME}/requestAdminCredential?api-version=${API_VERSION}" \
  --verbose 2>/tmp/admin-credential-headers.txt

ASYNC_URL=$(grep -i "Azure-AsyncOperation" /tmp/admin-credential-headers.txt | head -1 | sed -n "s/.*'\(https:[^']*\)'.*/\1/p")
LOCATION_URL=$(grep -i "Location" /tmp/admin-credential-headers.txt | head -1 | sed -n "s/.*'\(https:[^']*\)'.*/\1/p")

echo "Async URL: $ASYNC_URL"
echo "Location URL: $LOCATION_URL"

az rest --method GET --uri "$LOCATION_URL" | jq -r '.kubeconfig' > kubeconfig

KUBECONFIG="$(cat "kubeconfig")"

echo $KUBECONFIG

echo "Break glass done"

echo "Set auth vars"
# Display name for the Entra app registration
APP_DISPLAY_NAME="${CLUSTER_NAME}-auth"

# External auth resource name (used in Bicep and OpenShift secret name)
EXTERNAL_AUTH_NAME="entra"
TENANT_ID=$(az account show --query tenantId --output tsv)
ISSUER_URL="https://login.microsoftonline.com/${TENANT_ID}/v2.0"


echo "Get callback URL"

OAUTH_CALLBACK_URL=$(az rest \
  --method GET \
  --uri "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${CUSTOMER_RG_NAME}/providers/Microsoft.RedHatOpenShift/hcpOpenShiftClusters/${CLUSTER_NAME}?api-version=${API_VERSION}" \
  | jq -r '.properties.console.url')/auth/callback

echo "Callback URL: $OAUTH_CALLBACK_URL"

echo
echo
echo "Register Entra app"
echo

CLIENT_ID=$(az ad app create \
  --display-name "${APP_DISPLAY_NAME}" \
  --web-redirect-uris "${OAUTH_CALLBACK_URL}" http://localhost:8000 \
  --query appId --output tsv)

CLIENT_SECRET=$(az ad app credential reset \
  --id "${CLIENT_ID}" \
  --query password --output tsv)

az ad app update \
  --id "${CLIENT_ID}" \
  --optional-claims @manifest.json

echo
echo "Add email to graph"

az ad app permission add \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions 64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0=Scope \
  --id "${CLIENT_ID}"

az ad app update \
  --id "${CLIENT_ID}" \
  --set groupMembershipClaims=SecurityGroup


echo
echo " Deploy external auth provider"
echo

az deployment group create \
  --name 'aro-hcp-auth' \
  --subscription "${SUBSCRIPTION_ID}" \
  --resource-group "${CUSTOMER_RG_NAME}" \
  --template-file externalauth.bicep \
  --parameters \
    externalAuthName="${EXTERNAL_AUTH_NAME}" \
    issuerURL="${ISSUER_URL}" \
    clientID="${CLIENT_ID}" \
    clusterName="${CLUSTER_NAME}"

echo
echo "Verify auth config"
echo

az rest \
  --method GET \
  --uri "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${CUSTOMER_RG_NAME}/providers/Microsoft.RedHatOpenShift/hcpOpenShiftClusters/${CLUSTER_NAME}/externalAuths/${EXTERNAL_AUTH_NAME}?api-version=${API_VERSION}" \
  --query "properties.provisioningState" -o tsv

echo
echo "Create client secret"
echo

oc create secret generic "${EXTERNAL_AUTH_NAME}-console-openshift-console" \
  --namespace openshift-config \
  --from-literal=clientSecret="${CLIENT_SECRET}"


echo 
echo "Group claim anyone?"
echo

az rest --method GET --url "https://graph.microsoft.com/v1.0/me/memberOf" \
  --query "value[].{Name:displayName, Id:id}" -o table


az rest \
  --method GET \
  --uri "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${CUSTOMER_RG_NAME}/providers/Microsoft.RedHatOpenShift/hcpOpenShiftClusters/${CLUSTER_NAME}?api-version=2025-12-23-preview" \
  --query "properties.console.url" -o tsv