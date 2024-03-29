#!/bin/bash -v

curl -fL https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF > /etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt-get update
apt-get install -y kubelet="${k8s_version}*" kubeadm="${k8s_version}*" kubectl="${k8s_version}*" kubernetes-cni docker.io python-pip jq

# Kubelet with azure provider fix.
curl -fL https://milpa-builds.s3.amazonaws.com/kubelet > /usr/bin/kubelet
chmod 755 /usr/bin/kubelet

# Docker sets the policy for the FORWARD chain to DROP, change it back.
iptables -P FORWARD ACCEPT

if [ -z ${k8s_version} ]; then
    k8s_version=$(curl -fL https://storage.googleapis.com/kubernetes-release/release/stable.txt)
else
    k8s_version=v${k8s_version}
fi

# Export userdata template substitution variables.
export pod_cidr='${pod_cidr}'
export service_cidr='${service_cidr}'
export subnet_cidrs='${subnet_cidrs}'
export node_nametag='${node_nametag}'
export default_instance_type='${default_instance_type}'
export default_volume_size='${default_volume_size}'
export boot_image_tags='${boot_image_tags}'
export license_key='${license_key}'
export license_id='${license_id}'
export license_username='${license_username}'
export license_password='${license_password}'
export itzo_url='${itzo_url}'
export itzo_version='${itzo_version}'
export milpa_image='${milpa_image}'
export azure_subscription_id='${azure_subscription_id}'
export azure_tenant_id='${azure_tenant_id}'
export azure_client_id='${azure_client_id}'
export azure_client_secret='${azure_client_secret}'
export location='${location}'

mkdir -p /etc/kubernetes
cat <<EOF > /etc/kubernetes/cloud.conf
{
    "cloud":"AzurePublicCloud",
    "subscriptionId": "${azure_subscription_id}",
    "tenantId": "${azure_tenant_id}",
    "aadClientId": "${azure_client_id}",
    "aadClientSecret": "${azure_client_secret}",
    "resourceGroup": "${resource_group}",
    "location": "${location}",
    "subnetName": "${subnet_name}",
    "securityGroupName": "kiyot-security-group",
    "vnetName": "${vnet_name}",
    "vnetResourceGroup": "${resource_group}",
    "routeTableName": "${route_table_name}",
    "routeTableResourceGroup": "${resource_group}",
    "cloudProviderBackoff": false,
    "useManagedIdentityExtension": false,
    "useInstanceMetadata": false,
}
EOF

# Set CIDRs for ip-masq-agent.
non_masquerade_cidrs="${pod_cidr}"
for subnet in ${subnet_cidrs}; do
    non_masquerade_cidrs="$non_masquerade_cidrs, $subnet"
done
export non_masquerade_cidrs="$non_masquerade_cidrs"

cat <<EOF > /tmp/kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta1
kind: InitConfiguration
bootstrapTokens:
- groups:
  - system:bootstrappers:kubeadm:default-node-token
  token: ${k8stoken}
nodeRegistration:
  name: ${node_name}
  kubeletExtraArgs:
    cloud-provider: azure
    cloud-config: /etc/kubernetes/cloud.conf
$(if [[ "${network_plugin}" = "kubenet" ]]; then
    echo '    network-plugin: kubenet'
    echo '    non-masquerade-cidr: 0.0.0.0/0'
fi)
---
apiVersion: kubeadm.k8s.io/v1beta1
kind: ClusterConfiguration
networking:
  podSubnet: ${pod_cidr}
  serviceSubnet: ${service_cidr}
apiServer:
  certSANs:
  - 127.0.0.1
  - localhost
  extraArgs:
    enable-admission-plugins: DefaultStorageClass,NodeRestriction
    cloud-provider: azure
    cloud-config: /etc/kubernetes/cloud.conf
    feature-gates: "CSINodeInfo=true,CSIDriverRegistry=true,CSIBlockVolume=true,VolumeSnapshotDataSource=true"
    allow-privileged: "true"
  extraVolumes:
  - name: cloud
    hostPath: "/etc/kubernetes/cloud.conf"
    mountPath: "/etc/kubernetes/cloud.conf"
controllerManager:
  extraArgs:
    cloud-provider: azure
    cloud-config: /etc/kubernetes/cloud.conf
$(if [[ "${configure_cloud_routes}" = "true" ]]; then
    echo '    configure-cloud-routes: "true"'
else
    echo '    configure-cloud-routes: "false"'
fi)
    address: 0.0.0.0
  extraVolumes:
  - name: cloud
    hostPath: "/etc/kubernetes/cloud.conf"
    mountPath: "/etc/kubernetes/cloud.conf"
kubernetesVersion: "$k8s_version"
# Enable kube-proxy masqueradeAll if kiyot-kube-proxy is enabled.
#---
#apiVersion: kubeproxy.config.k8s.io/v1alpha1
#kind: KubeProxyConfiguration
#iptables:
#  masqueradeAll: true
EOF
kubeadm init --config=/tmp/kubeadm-config.yaml

export KUBECONFIG=/etc/kubernetes/admin.conf

# Configure kubectl.
mkdir -p /home/ubuntu/.kube
sudo cp -i $KUBECONFIG /home/ubuntu/.kube/config
sudo chown ubuntu: /home/ubuntu/.kube/config

# Set server-url for kiyot.
export server_url="$(kubectl config view -ojsonpath='{.clusters[0].cluster.server}')"

# Networking.
if [[ "${network_plugin}" != "kubenet" ]]; then
    curl -fL https://raw.githubusercontent.com/elotl/milpa-deploy/master/deploy/cni/${network_plugin}.yaml | envsubst | kubectl apply -f -
fi

# Create a default storage class, backed by Azure Disk.
curl -fL https://raw.githubusercontent.com/elotl/milpa-deploy/master/deploy/storageclass-azure-disk.yaml | envsubst | kubectl apply -f -

# Set up ip-masq-agent.
curl -fL https://raw.githubusercontent.com/elotl/milpa-deploy/master/deploy/ip-masq-agent.yaml | envsubst | kubectl apply -f -

# Azure cloud provider RBAC configuration.
curl -fL https://raw.githubusercontent.com/elotl/milpa-deploy/master/deploy/azure-cloud-provider.yaml | envsubst | kubectl apply -f -

# Deploy Kiyot/Milpa components.
curl -fL https://raw.githubusercontent.com/elotl/milpa-deploy/master/deploy/kiyot.yaml | envsubst | kubectl apply -f -

curl -fL https://raw.githubusercontent.com/elotl/milpa-deploy/master/deploy/milpa-config-azure.yaml | envsubst | kubectl apply -f -

# Uncomment this if the fargate backend is in use. In that case, we also need
# to start a kube-proxy pod for cells, since fargate cells don't have their own
# service proxy running.
#curl -fL https://raw.githubusercontent.com/elotl/milpa-deploy/master/deploy/kiyot-kube-proxy.yaml | envsubst | kubectl apply -f -

curl -fL https://raw.githubusercontent.com/elotl/milpa-deploy/master/deploy/kiyot-device-plugin.yaml | envsubst | kubectl apply -f -

curl -fL https://raw.githubusercontent.com/elotl/milpa-deploy/master/deploy/create-webhook.sh | bash
