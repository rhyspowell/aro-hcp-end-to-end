# Check that appropriate services are enabled
az provider list --query "[?namespace=='Microsoft.RedHatOpenShift'].registrationState"
az provider list --query "[?namespace=='Microsoft.Compute'].registrationState" 
az provider list --query "[?namespace=='Microsoft.Storage'].registrationState" 
az provider list --query "[?namespace=='Microsoft.Authorization'].registrationState"



# Grab the pull secret
PULLSECRET=""
CUSTOM_DOMAIN=""

# Azure resource location and subscription
LOCATION="uksouth"
SUBSCRIPTION_ID="$(az account show --query id --output tsv)"

# check openshift is registered TODO: if not registered add the bits below the query
az provider list --query "[?namespace=='Microsoft.RedHatOpenShift'].registrationState" --output tsv

# az provider register --namespace Microsoft.RedHatOpenShift --wait
# az provider register --namespace Microsoft.Compute --wait
# az provider register --namespace Microsoft.Storage --wait
# az provider register --namespace Microsoft.Authorization --wait

CUSTOMER_RG_NAME="ocp5-rhpowell-1"

# Network resources
CUSTOMER_NSG="ocp5-rhys-nsg"
CUSTOMER_VNET_NAME="ocp5-rhys-vnet"
CUSTOMER_VNET_SUBNET1="ocp5-rhys-worker"
CUSTOMER_VNET_INTEGRATION_SUBNET_NAME="ocp5-rhys-peer-subnet"

# Cluster and node pool
CLUSTER_NAME="ocp5-rhys"
MANAGED_RESOURCE_GROUP="${CLUSTER_NAME}-managed-rg"
NP_NAME="rhys-orig-np"
API_VERSION="2025-12-23-preview"
CLUSTER_VERSION="5.0.0-rc.5"    # Example: 4.20
NP_VERSION="5.0.0-rc.5"   # Example: 4.20.8
CHANNEL_GROUP="candidate"

# create RG
az group create --name "${CUSTOMER_RG_NAME}" --subscription "${SUBSCRIPTION_ID}" --location "${LOCATION}"

# create networking
## create network security group
az network nsg create --name "${CUSTOMER_NSG}" --resource-group "${CUSTOMER_RG_NAME}" --location "${LOCATION}"
## create vnet with worker subnet
az network vnet create --name "${CUSTOMER_VNET_NAME}" --resource-group "${CUSTOMER_RG_NAME}" --location "${LOCATION}" --address-prefixes 10.0.0.0/16 --subnet-name "${CUSTOMER_VNET_SUBNET1}" --subnet-prefixes 10.0.0.0/24 --nsg "${CUSTOMER_NSG}"
## create the integration subnet
az network vnet subnet create --name "${CUSTOMER_VNET_INTEGRATION_SUBNET_NAME}" --vnet-name "${CUSTOMER_VNET_NAME}" --resource-group "${CUSTOMER_RG_NAME}" --address-prefixes 10.0.1.0/24 --network-security-group "${CUSTOMER_NSG}" --delegations Microsoft.RedHatOpenShift/hcpOpenShiftClusters
## Grab the IDs of the created resources
NSG_ID=$(az network nsg show --name "${CUSTOMER_NSG}" --resource-group "${CUSTOMER_RG_NAME}" --query id --output tsv)
SUBNET_ID=$(az network vnet subnet show --name "${CUSTOMER_VNET_SUBNET1}" --vnet-name "${CUSTOMER_VNET_NAME}" --resource-group "${CUSTOMER_RG_NAME}" --query id --output tsv)
VNET_ID=$(az network vnet show --name "${CUSTOMER_VNET_NAME}" --resource-group "${CUSTOMER_RG_NAME}" --query id --output tsv)
VNET_INTEGRATION_SUBNET_ID=$(az network vnet subnet show --name "${CUSTOMER_VNET_INTEGRATION_SUBNET_NAME}" --vnet-name "${CUSTOMER_VNET_NAME}" --resource-group "${CUSTOMER_RG_NAME}" --query id --output tsv)

# Create Managed Identities
## Control plane operator identities
az identity create --name "${CLUSTER_NAME}-cp-cluster-api-azure" --resource-group "${CUSTOMER_RG_NAME}"
az identity create --name "${CLUSTER_NAME}-cp-control-plane" --resource-group "${CUSTOMER_RG_NAME}"
az identity create --name "${CLUSTER_NAME}-cp-cloud-controller-manager" --resource-group "${CUSTOMER_RG_NAME}"
az identity create --name "${CLUSTER_NAME}-cp-ingress" --resource-group "${CUSTOMER_RG_NAME}"
az identity create --name "${CLUSTER_NAME}-cp-disk-csi-driver" --resource-group "${CUSTOMER_RG_NAME}"
az identity create --name "${CLUSTER_NAME}-cp-file-csi-driver" --resource-group "${CUSTOMER_RG_NAME}"
az identity create --name "${CLUSTER_NAME}-cp-image-registry" --resource-group "${CUSTOMER_RG_NAME}"
az identity create --name "${CLUSTER_NAME}-cp-cloud-network-config" --resource-group "${CUSTOMER_RG_NAME}"
az identity create --name "${CLUSTER_NAME}-cp-kms" --resource-group "${CUSTOMER_RG_NAME}"

## Data plane operator identities
az identity create --name "${CLUSTER_NAME}-dp-disk-csi-driver" --resource-group "${CUSTOMER_RG_NAME}"
az identity create --name "${CLUSTER_NAME}-dp-file-csi-driver" --resource-group "${CUSTOMER_RG_NAME}"
az identity create --name "${CLUSTER_NAME}-dp-image-registry" --resource-group "${CUSTOMER_RG_NAME}"

##   Service managed identity
az identity create --name "${CLUSTER_NAME}-service-managed-identity" --resource-group "${CUSTOMER_RG_NAME}"

# get all the IDs
## Control plane identity resource IDs and principal IDs
CLUSTER_API_AZURE_MI_ID=$(az identity show --name "${CLUSTER_NAME}-cp-cluster-api-azure" --resource-group "${CUSTOMER_RG_NAME}" --query id --output tsv)
CLUSTER_API_AZURE_MI_PID=$(az identity show --name "${CLUSTER_NAME}-cp-cluster-api-azure" --resource-group "${CUSTOMER_RG_NAME}" --query principalId --output tsv)

CONTROL_PLANE_MI_ID=$(az identity show --name "${CLUSTER_NAME}-cp-control-plane" --resource-group "${CUSTOMER_RG_NAME}" --query id --output tsv)
CONTROL_PLANE_MI_PID=$(az identity show --name "${CLUSTER_NAME}-cp-control-plane" --resource-group "${CUSTOMER_RG_NAME}" --query principalId --output tsv)

CLOUD_CONTROLLER_MANAGER_MI_ID=$(az identity show --name "${CLUSTER_NAME}-cp-cloud-controller-manager" --resource-group "${CUSTOMER_RG_NAME}" --query id --output tsv)
CLOUD_CONTROLLER_MANAGER_MI_PID=$(az identity show --name "${CLUSTER_NAME}-cp-cloud-controller-manager" --resource-group "${CUSTOMER_RG_NAME}" --query principalId --output tsv)

INGRESS_MI_ID=$(az identity show --name "${CLUSTER_NAME}-cp-ingress" --resource-group "${CUSTOMER_RG_NAME}" --query id --output tsv)
INGRESS_MI_PID=$(az identity show --name "${CLUSTER_NAME}-cp-ingress" --resource-group "${CUSTOMER_RG_NAME}" --query principalId --output tsv)

DISK_CSI_DRIVER_MI_ID=$(az identity show --name "${CLUSTER_NAME}-cp-disk-csi-driver" --resource-group "${CUSTOMER_RG_NAME}" --query id --output tsv)

FILE_CSI_DRIVER_MI_ID=$(az identity show --name "${CLUSTER_NAME}-cp-file-csi-driver" --resource-group "${CUSTOMER_RG_NAME}" --query id --output tsv)
FILE_CSI_DRIVER_MI_PID=$(az identity show --name "${CLUSTER_NAME}-cp-file-csi-driver" --resource-group "${CUSTOMER_RG_NAME}" --query principalId --output tsv)

IMAGE_REGISTRY_MI_ID=$(az identity show --name "${CLUSTER_NAME}-cp-image-registry" --resource-group "${CUSTOMER_RG_NAME}" --query id --output tsv)
IMAGE_REGISTRY_MI_PID=$(az identity show --name "${CLUSTER_NAME}-cp-image-registry" --resource-group "${CUSTOMER_RG_NAME}" --query principalId --output tsv)

CLOUD_NETWORK_CONFIG_MI_ID=$(az identity show --name "${CLUSTER_NAME}-cp-cloud-network-config" --resource-group "${CUSTOMER_RG_NAME}" --query id --output tsv)
CLOUD_NETWORK_CONFIG_MI_PID=$(az identity show --name "${CLUSTER_NAME}-cp-cloud-network-config" --resource-group "${CUSTOMER_RG_NAME}" --query principalId --output tsv)

KMS_MI_ID=$(az identity show --name "${CLUSTER_NAME}-cp-kms" --resource-group "${CUSTOMER_RG_NAME}" --query id --output tsv)
KMS_MI_PID=$(az identity show --name "${CLUSTER_NAME}-cp-kms" --resource-group "${CUSTOMER_RG_NAME}" --query principalId --output tsv)

## Data plane identity resource IDs and principal IDs
DP_DISK_CSI_DRIVER_MI_ID=$(az identity show --name "${CLUSTER_NAME}-dp-disk-csi-driver" --resource-group "${CUSTOMER_RG_NAME}" --query id --output tsv)

DP_FILE_CSI_DRIVER_MI_ID=$(az identity show --name "${CLUSTER_NAME}-dp-file-csi-driver" --resource-group "${CUSTOMER_RG_NAME}" --query id --output tsv)
DP_FILE_CSI_DRIVER_MI_PID=$(az identity show --name "${CLUSTER_NAME}-dp-file-csi-driver" --resource-group "${CUSTOMER_RG_NAME}" --query principalId --output tsv)

DP_IMAGE_REGISTRY_MI_ID=$(az identity show --name "${CLUSTER_NAME}-dp-image-registry" --resource-group "${CUSTOMER_RG_NAME}" --query id --output tsv)
DP_IMAGE_REGISTRY_MI_PID=$(az identity show --name "${CLUSTER_NAME}-dp-image-registry" --resource-group "${CUSTOMER_RG_NAME}" --query principalId --output tsv)

## Service managed identity resource ID and principal ID
SERVICE_MI_ID=$(az identity show --name "${CLUSTER_NAME}-service-managed-identity" --resource-group "${CUSTOMER_RG_NAME}" --query id --output tsv)
SERVICE_MI_PID=$(az identity show --name "${CLUSTER_NAME}-service-managed-identity" --resource-group "${CUSTOMER_RG_NAME}" --query principalId --output tsv)

az deployment group create \
  --name 'rhys-aro-hcp' \
  --subscription "${SUBSCRIPTION_ID}" \
  --resource-group "${CUSTOMER_RG_NAME}" \
  --template-file cluster.bicep \
  --parameters \
    customerNsgName="${CUSTOMER_NSG}" \
    customerVnetName="${CUSTOMER_VNET_NAME}" \
    customerVirtualNetworkIntegrationSubnetName="${CUSTOMER_VNET_INTEGRATION_SUBNET_NAME}" \
    customerVnetSubnetName="${CUSTOMER_VNET_SUBNET1}" \
    clusterName="${CLUSTER_NAME}" \
    managedResourceGroupName="${MANAGED_RESOURCE_GROUP}" \
    nodePoolName="${NP_NAME}" \
    clusterVersion="${CLUSTER_VERSION}" \
    nodePoolVersion="${NP_VERSION}" \
    apiVisibility="Public" \
    privateKeyVault=false

az rest \
  --method GET \
  --uri "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${CUSTOMER_RG_NAME}/providers/Microsoft.RedHatOpenShift/hcpOpenShiftClusters/${CLUSTER_NAME}?api-version=2025-12-23-preview" \
  --query "properties.provisioningState" \
  --output tsv

echo "Grab access details"

az rest \
  --method POST \
  --uri "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${CUSTOMER_RG_NAME}/providers/Microsoft.RedHatOpenShift/hcpOpenShiftClusters/${CLUSTER_NAME}/requestAdminCredential?api-version=${API_VERSION}" \
  --verbose 2>/tmp/admin-credential-headers.txt

ASYNC_URL=$(grep -i "Azure-AsyncOperation" /tmp/admin-credential-headers.txt | head -1 | sed -n "s/.*'\(https:[^']*\)'.*/\1/p")
LOCATION_URL=$(grep -i "Location" /tmp/admin-credential-headers.txt | head -1 | sed -n "s/.*'\(https:[^']*\)'.*/\1/p")

echo "Async URL: $ASYNC_URL"
echo "Location URL: $LOCATION_URL"

az rest --method GET --uri "$LOCATION_URL" | jq -r '.kubeconfig' > kubeconfig

echo "now run the following"
echo
echo "export KUBECONFIG=kubeconfig"
echo "oc auth whoami"
