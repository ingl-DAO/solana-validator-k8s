"""CKV_SOLANA_2 — Solana P2P rules must be stateless.

OCI enforces stateful security rules with a per-VNIC connection-tracking table whose size is fixed
by the shape. Solana's UDP volume from thousands of gossip peers fills it, and the failure mode is
symptom-free packet loss: no error, no counter, no log line. Oracle recommends stateless rules for
high-volume internet-facing traffic. See docs/decisions/0006.
"""
from checkov.common.models.enums import CheckCategories, CheckResult
from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck

P2P_MIN, P2P_MAX = 8000, 8026


class P2PRulesStateless(BaseResourceCheck):
    def __init__(self):
        super().__init__(
            name="Solana P2P security rules (8000-8026) must be stateless",
            id="CKV_SOLANA_2",
            categories=[CheckCategories.NETWORKING],
            supported_resources=["oci_core_network_security_group_security_rule"],
        )

    def scan_resource_conf(self, conf):
        if not self._touches_p2p(conf):
            return CheckResult.PASSED
        stateless = conf.get("stateless", [False])
        stateless = stateless[0] if isinstance(stateless, list) and stateless else stateless
        return CheckResult.PASSED if stateless is True else CheckResult.FAILED

    @staticmethod
    def _touches_p2p(conf):
        for proto in ("tcp_options", "udp_options"):
            for block in conf.get(proto, []) or []:
                if not isinstance(block, dict):
                    continue
                for field in ("destination_port_range", "source_port_range"):
                    for rng in block.get(field, []) or []:
                        if not isinstance(rng, dict):
                            continue
                        try:
                            lo = int(rng.get("min", [None])[0] if isinstance(rng.get("min"), list) else rng.get("min"))
                            hi = int(rng.get("max", [None])[0] if isinstance(rng.get("max"), list) else rng.get("max"))
                        except (TypeError, ValueError):
                            continue
                        # any overlap with the P2P range
                        if lo <= P2P_MAX and hi >= P2P_MIN:
                            return True
        return False


check = P2PRulesStateless()
