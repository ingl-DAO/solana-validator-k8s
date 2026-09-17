output "cluster_id" {
  value = oci_containerengine_cluster.this.id
}

output "kubeconfig_command" {
  description = "The seam. Everything past this point is portable."
  value       = "oci ce cluster create-kubeconfig --cluster-id ${oci_containerengine_cluster.this.id} --file $HOME/.kube/config --region ${var.region} --token-version 2.0.0 --kube-endpoint PUBLIC_ENDPOINT"
}

output "storage_class_name" {
  description = "Feed to the chart as persistence.storageClassName"
  value       = kubernetes_storage_class_v1.oci_bv_hp.metadata[0].name
}

output "contract_satisfied" {
  description = "Which contract requirements this module implements. See ../README.md"
  value = {
    "1_cluster"         = "OKE Basic ${var.kubernetes_version}"
    "2_storageclass"    = "oci-bv-hp, 20 VPU = 75 IOPS/GB, expansion on, Retain"
    "3_public_udp"      = "NSG stateless UDP+TCP 8000-8026 from 0.0.0.0/0"
    "4_nat"             = "OCI 1:1 NAT, public IP on worker VNIC"
    "5_sysctls"         = "cloud-init/worker-init.sh"
    "6_runtime_rlimits" = "containerd drop-in, LimitNOFILE=1000000 LimitMEMLOCK=infinity"
    "7_seccomp"         = "OKE Basic does not enforce PodSecurity restricted by default"
    "8_egress"          = "IGW + all-protocol egress rule"
  }
}
