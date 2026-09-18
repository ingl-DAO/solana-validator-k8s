# The kubernetes provider is configured from the cluster this module creates, so the StorageClass
# lands in the same apply. That is the only place these two layers touch.
provider "kubernetes" {
  host                   = data.oci_containerengine_cluster_kube_config.this.content != "" ? yamldecode(data.oci_containerengine_cluster_kube_config.this.content).clusters[0].cluster.server : ""
  cluster_ca_certificate = base64decode(yamldecode(data.oci_containerengine_cluster_kube_config.this.content).clusters[0].cluster["certificate-authority-data"])
  # The exec plugin runs `oci` as a subprocess, so it needs the SAME auth the provider uses.
  # Without --profile and --auth it defaults to api-key auth against [DEFAULT] and fails with
  #   getting credentials: exec: executable oci failed with exit code 1
  # which says nothing about profiles or tokens.
  #
  # `oci` must also be on PATH for the terraform process. pipx installs it to ~/.local/bin, which
  # a non-login shell may not have.
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "oci"
    args = [
      "ce", "cluster", "generate-token",
      "--cluster-id", oci_containerengine_cluster.this.id,
      "--region", var.region,
      "--profile", var.oci_config_profile,
      "--auth", var.oci_auth == "SecurityToken" ? "security_token" : "api_key",
    ]
  }
}

data "oci_containerengine_cluster_kube_config" "this" {
  cluster_id    = oci_containerengine_cluster.this.id
  token_version = "2.0.0"
}
