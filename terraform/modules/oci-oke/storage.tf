# The StorageClass is defined HERE, in the infra layer, not in the chart. The chart takes
# persistence.storageClassName as a value and never defines one. That is the seam.
# Contract requirement #2: allowVolumeExpansion, WaitForFirstConsumer, Retain, >=75 IOPS/GB.
resource "kubernetes_storage_class_v1" "oci_bv_hp" {
  metadata {
    name = "oci-bv-hp"
  }
  storage_provisioner = "blockvolume.csi.oraclecloud.com"
  parameters = {
    attachment-type = "paravirtualized"
    # Higher Performance: 75 IOPS/GB, 600 KBPS/GB.
    # Balanced (10 VPU) caps at 25k IOPS/volume and is marginal for accounts-DB write
    # amplification. Ultra High Performance is UNREACHABLE on any shape provisionable here: it
    # requires multipath attachment, which requires >=16 OCPU on E4/E5/E6 flex. Capability gate,
    # not a money gate. This is the arithmetic behind "mainnet accounts DB on cloud block storage
    # is a thing I deliberately did not attempt" in LIMITATIONS.md.
    vpusPerGB = "20"
  }
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  # Retain, so the ledger survives scaling the node pool to 0 overnight. Losing it would mean a
  # fresh snapshot fetch every morning.
  reclaim_policy = "Retain"
}
