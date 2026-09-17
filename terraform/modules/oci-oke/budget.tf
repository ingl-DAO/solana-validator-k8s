# Spend guardrail.
#
# The realistic failure mode on this project is not arithmetic, it is inattention: finishing a
# session and forgetting `make pause`. At the E5 8/96 shape that costs roughly $10.40/day, so a
# forgotten week costs more than the entire planned build.
#
# A trial tenancy cannot produce a surprise invoice — it does not auto-convert to pay-as-you-go,
# and Oracle stops and reclaims resources when credits are exhausted. So the thing being protected
# here is the ENVIRONMENT and the remaining trial days, not your bank account.
#
# Budgets are denominated in the tenancy's own currency, which for this tenancy is EUR.

locals {
  tenancy_ocid = var.tenancy_ocid != "" ? var.tenancy_ocid : var.compartment_id
}

resource "oci_budget_budget" "trial" {
  # Budgets live in the root compartment (the tenancy).
  compartment_id = local.tenancy_ocid
  display_name   = "${var.name_prefix}-trial-guardrail"
  description    = "Spend guardrail for solana-validator-k8s during the OCI free trial"

  amount       = var.budget_amount
  reset_period = "MONTHLY"

  target_type = "COMPARTMENT"
  targets     = [var.compartment_id]
}

# Early warning. 20% of EUR 250 = EUR 50 — roughly five forgotten days.
resource "oci_budget_alert_rule" "actual_20" {
  budget_id      = oci_budget_budget.trial.id
  display_name   = "${var.name_prefix}-actual-20pct"
  type           = "ACTUAL"
  threshold      = 20
  threshold_type = "PERCENTAGE"
  recipients     = join(",", var.budget_alert_email)
  message        = "solana-validator-k8s: 20% of the trial budget spent. If no session is running, check `make pause` was applied."
}

# Serious. 40% = EUR 100.
resource "oci_budget_alert_rule" "actual_40" {
  budget_id      = oci_budget_budget.trial.id
  display_name   = "${var.name_prefix}-actual-40pct"
  type           = "ACTUAL"
  threshold      = 40
  threshold_type = "PERCENTAGE"
  recipients     = join(",", var.budget_alert_email)
  message        = "solana-validator-k8s: 40% of the trial budget spent. Capture evidence early; the environment is at risk before the calendar deadline."
}

# The one that actually saves you: fires on TREND, not on damage already done. A node left running
# after a session trips this within a day or so, long before the actual-spend rules would.
resource "oci_budget_alert_rule" "forecast_80" {
  budget_id      = oci_budget_budget.trial.id
  display_name   = "${var.name_prefix}-forecast-80pct"
  type           = "FORECAST"
  threshold      = 80
  threshold_type = "PERCENTAGE"
  recipients     = join(",", var.budget_alert_email)
  message        = "solana-validator-k8s: forecast to reach 80% of budget. Something is running that should not be. Run `make pause`."
}
