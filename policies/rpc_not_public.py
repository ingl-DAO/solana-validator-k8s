"""CKV_SOLANA_1 — the Solana JSON-RPC ports must never be open to the internet.

The validator binds RPC to 127.0.0.1 and the exporter reaches it over loopback inside the shared
host network namespace, so these ports should not appear in any security rule. An open Solana RPC
endpoint is a documented abuse vector.
"""
from checkov.common.models.enums import CheckCategories, CheckResult
from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck

RPC_PORTS = (8899, 8900)
PUBLIC = ("0.0.0.0/0", "::/0")


class RpcNotPublic(BaseResourceCheck):
    def __init__(self):
        super().__init__(
            name="Solana JSON-RPC (8899/8900) must not be reachable from the internet",
            id="CKV_SOLANA_1",
            categories=[CheckCategories.NETWORKING],
            supported_resources=["oci_core_network_security_group_security_rule"],
        )

    def scan_resource_conf(self, conf):
        if self._str(conf, "direction") != "INGRESS":
            return CheckResult.PASSED
        if self._str(conf, "source") not in PUBLIC:
            return CheckResult.PASSED

        for proto in ("tcp_options", "udp_options"):
            for block in conf.get(proto, []) or []:
                if not isinstance(block, dict):
                    continue
                for rng in block.get("destination_port_range", []) or []:
                    if not isinstance(rng, dict):
                        continue
                    lo = self._int(rng, "min")
                    hi = self._int(rng, "max")
                    if lo is None or hi is None:
                        continue
                    if any(lo <= p <= hi for p in RPC_PORTS):
                        return CheckResult.FAILED
        return CheckResult.PASSED

    @staticmethod
    def _str(conf, key):
        v = conf.get(key, [None])
        v = v[0] if isinstance(v, list) and v else v
        return v

    @classmethod
    def _int(cls, conf, key):
        v = cls._str(conf, key)
        try:
            return int(v)
        except (TypeError, ValueError):
            return None


check = RpcNotPublic()
