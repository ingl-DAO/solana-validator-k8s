# Local: no cloud, no credentials

This is the portability proof. The same chart that runs the testnet follower on OKE runs here on
kind, in `mode: test-validator`, with no cloud account and no Terraform at all.

```
make dev-up      # kind cluster + chart, tier 1
make dev-down
```

If this works and OKE works, the chart is portable by demonstration rather than by assertion.
The infra contract those two environments both satisfy is in [`../modules/README.md`](../modules/README.md).
