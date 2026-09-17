# The kubernetes provider is configured from the cluster this module creates, so the StorageClass
# lands in the same apply. That is the only place these two layers touch.
provider "kubernetes" {
  host                   = data.oci_containerengine_cluster_kube_config.this.content != "" ? yamldecode(data.oci_containerengine_cluster_kube_config.this.content).clusters[0].cluster.server : ""
  cluster_ca_certificate = base64decode(yamldecode(data.oci_containerengine_cluster_kube_config.this.content).clusters[0].cluster["certificate-authority-data"])
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "oci"
    args = [
      "ce", "cluster", "generate-token",
      "--cluster-id", oci_containerengine_cluster.this.id,
      "--region", var.region,
    ]
  }
}

data "oci_containerengine_cluster_kube_config" "this" {
  cluster_id    = oci_containerengine_cluster.this.id
  token_version = "2.0.0"
}
