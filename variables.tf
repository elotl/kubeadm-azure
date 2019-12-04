variable "cluster-name" {
}

# Azure subscription ID.
variable "azure-subscription-id" {
}

# Azure tenant ID.
variable "azure-tenant-id" {
}

# Azure client ID.
variable "azure-client-id" {
}

# Azure client secret.
variable "azure-client-secret" {
}

variable "ssh-key-path" {
  default = "~/.ssh/id_rsa.pub"
}

variable "itzo-url" {
  // The URL to download the node agent from.
  default = "http://itzo-download.s3.amazonaws.com"
}

variable "itzo-version" {
  // The version of node agent to use.
  default = "latest"
}

variable "default-instance-type" {
  // This this the default cloud instance type. Pods that don't specify their
  // cpu and memory requirements will be launched on this instance type.
  // Example: "t3.nano".
  default = "Basic_A0"
}

variable "default-volume-size" {
  // This this the default volume size used on the cloud instance. Example: "15Gi".
  default = "10Gi"
}

variable "boot-image-tags" {
  // This is a JSON dictionary of key-value pairs, describing the image tags
  // Milpa will use when finding the AMI to launch cloud instances with. Only
  // change it when you know what you are doing.
  default = {
    "company" = "elotl"
    "product" = "milpa"
  }
}

variable "license-key" {
  default = ""
}

variable "license-id" {
  default = ""
}

variable "license-username" {
  default = ""
}

variable "license-password" {
  default = ""
}

variable "location" {
  default = "East US"
}

variable "master-userdata" {
  default = "master.sh"
}

variable "worker-userdata" {
  default = "worker.sh"
}

variable "milpa-worker-userdata" {
  default = "milpa-worker.sh"
}

variable "vpc-cidr" {
  default = "10.0.0.0/16"
}

variable "pod-cidr" {
  default = "172.20.0.0/16"
}

variable "service-cidr" {
  default = "10.96.0.0/12"
}

# variable "workers" {
#   // Number of regular kubelet workers to create in the cluster.
#   default = 0
# }

# variable "milpa-workers" {
#   // Number of Milpa workers to create in the cluster.
#   default = 1
# }

variable "k8s-version" {
  // You can specify a specific version, for example "1.13.5", or "" for
  // using the latest version available. Don't include a trailing asterisk
  // that is appended by the install scripts.
  default = ""
}

variable "milpa-image" {
  default = "elotl/milpa"
}

variable "network-plugin" {
  default = "kubenet"
}

variable "configure-cloud-routes" {
  default = "true"
}
