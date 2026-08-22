-- Luna Telecom reviewed customer-service actions.
--
-- This DSL is the reviewable source of truth for model-facing inspection and
-- proposal capabilities. Compile it to telecom-actions.contract.json with:
--
--   synapsor-runner dsl compile ./telecom-actions.synapsor.sql \
--     --out ./telecom-actions.contract.json --strict
--
-- Runtime wiring and secrets remain in synapsor.runner.json.

CREATE AGENT CONTEXT telecom_customer
  BIND tenant_id FROM HTTP_CLAIM tenant_id REQUIRED
  BIND principal FROM HTTP_CLAIM sub REQUIRED
  TENANT BINDING tenant_id
  PRINCIPAL BINDING principal
END

-- ============================ Account plan ============================

CREATE CAPABILITY account.inspect_subscription
  DESCRIPTION 'Inspect one subscription in the authenticated account before discussing or proposing a plan change.'
  RETURNS HINT 'Returns reviewed plan facts, the row version, and an evidence handle.'
  USING CONTEXT telecom_customer
  SOURCE telecom_postgres
  ON telecom.subscriptions
  PRIMARY KEY subscription_id
  TENANT KEY account_id
  LOOKUP subscription_id BY subscription_id
  ARG subscription_id STRING REQUIRED MAX LENGTH 36 DESCRIPTION 'Reviewed subscription UUID returned by Explore.'
  ALLOW READ subscription_id, account_id, plan_code, plan_display_name, base_monthly_cents, included_lines, data_policy, international_day_pass, effective_from, contract_end_date, version, updated_at
  MODEL WITHHELD account_id
  REQUIRE EVIDENCE
  MAX ROWS 1
END

CREATE CAPABILITY account.propose_plan_change
  DESCRIPTION 'Propose changing the authenticated account plan. Use only after inspection and confirmation. Destination base prices at or below 16500 cents may be policy-approved within tenant daily circuit breakers.'
  RETURNS HINT 'Returns a proposal id and exact diff. A qualifying plan may be policy-approved, but source writeback remains a separate trusted operation.'
  USING CONTEXT telecom_customer
  SOURCE telecom_postgres
  ON telecom.subscriptions
  PRIMARY KEY subscription_id
  TENANT KEY account_id
  CONFLICT GUARD version
  LOOKUP subscription_id BY subscription_id
  ARG subscription_id STRING REQUIRED MAX LENGTH 36 DESCRIPTION 'Reviewed subscription UUID returned by Explore or inspection.'
  ARG plan_code STRING ENUM('starter', 'unlimited', 'unlimited_plus', 'family_premium') REQUIRED DESCRIPTION 'Exact reviewed destination plan.'
  ARG monthly_price_cents NUMBER REQUIRED MIN 4500 MAX 16500 DESCRIPTION 'Exact base monthly cents for the destination plan: starter 4500, unlimited 6500, unlimited_plus 13500, family_premium 16500.'
  ALLOW READ subscription_id, account_id, plan_code, plan_display_name, base_monthly_cents, included_lines, data_policy, international_day_pass, version, updated_at
  MODEL WITHHELD account_id
  REQUIRE EVIDENCE
  MAX ROWS 1
  PROPOSE ACTION account.propose_plan_change UPDATE
  ALLOW WRITE plan_code, base_monthly_cents
  PATCH plan_code = ARG plan_code
  PATCH base_monthly_cents = ARG monthly_price_cents
  BOUND base_monthly_cents 4500..16500
  APPROVAL ROLE support_supervisor
  AUTO APPROVE WHEN base_monthly_cents <= 16500
  LIMIT 3 PER DAY
  LIMIT TOTAL 30000 PER DAY
  WRITEBACK APP HANDLER EXECUTOR telecom_app_handler
END

-- =========================== Service lines ============================

CREATE CAPABILITY line.inspect_service_settings
  DESCRIPTION 'Inspect roaming and service settings for one line visible to the authenticated principal.'
  RETURNS HINT 'Returns reviewed line settings, row version, and an evidence handle.'
  USING CONTEXT telecom_customer
  SOURCE telecom_postgres
  ON telecom.service_lines
  PRIMARY KEY line_id
  TENANT KEY account_id
  LOOKUP line_id BY line_id
  ARG line_id STRING REQUIRED MAX LENGTH 36 DESCRIPTION 'Reviewed line UUID returned by Explore.'
  ALLOW READ line_id, account_id, subscriber_id, line_label, phone_last4, status, device_name, international_roaming_enabled, data_limit_gb, version, updated_at
  MODEL WITHHELD account_id, subscriber_id
  REQUIRE EVIDENCE
  MAX ROWS 1
END

CREATE CAPABILITY line.propose_roaming_change
  DESCRIPTION 'Propose enabling or disabling international roaming on a line the authenticated principal is allowed to manage.'
  RETURNS HINT 'Returns a review-required proposal id and exact diff; the source database is unchanged until external approval and app-owned apply.'
  USING CONTEXT telecom_customer
  SOURCE telecom_postgres
  ON telecom.service_lines
  PRIMARY KEY line_id
  TENANT KEY account_id
  CONFLICT GUARD version
  LOOKUP line_id BY line_id
  ARG line_id STRING REQUIRED MAX LENGTH 36 DESCRIPTION 'Reviewed line UUID returned by Explore or inspection.'
  ARG enabled BOOLEAN REQUIRED DESCRIPTION 'True to enable international roaming; false to disable it.'
  ALLOW READ line_id, account_id, subscriber_id, line_label, phone_last4, status, international_roaming_enabled, version, updated_at
  MODEL WITHHELD account_id, subscriber_id
  REQUIRE EVIDENCE
  MAX ROWS 1
  PROPOSE ACTION line.propose_roaming_change UPDATE
  ALLOW WRITE international_roaming_enabled
  PATCH international_roaming_enabled = ARG enabled
  APPROVAL ROLE support_supervisor
  WRITEBACK APP HANDLER EXECUTOR telecom_app_handler
END

-- ======================== Billing preferences =========================

CREATE CAPABILITY billing.inspect_preferences
  DESCRIPTION 'Inspect autopay and paperless billing preferences for the authenticated account owner or manager.'
  RETURNS HINT 'Returns reviewed billing preferences, row version, and an evidence handle.'
  USING CONTEXT telecom_customer
  SOURCE telecom_postgres
  ON telecom.billing_preferences
  PRIMARY KEY billing_preference_id
  TENANT KEY account_id
  LOOKUP billing_preference_id BY billing_preference_id
  ARG billing_preference_id STRING REQUIRED MAX LENGTH 36 DESCRIPTION 'Reviewed billing-preference UUID returned by Explore.'
  ALLOW READ billing_preference_id, account_id, autopay_enabled, paperless_billing, monthly_spend_alert_cents, payment_method_label, version, updated_at
  MODEL WITHHELD account_id
  REQUIRE EVIDENCE
  MAX ROWS 1
END

CREATE CAPABILITY billing.propose_autopay_change
  DESCRIPTION 'Propose enabling or disabling autopay for the authenticated account owner or manager.'
  RETURNS HINT 'Returns a review-required proposal id and exact diff; the source database is unchanged until external approval and app-owned apply.'
  USING CONTEXT telecom_customer
  SOURCE telecom_postgres
  ON telecom.billing_preferences
  PRIMARY KEY billing_preference_id
  TENANT KEY account_id
  CONFLICT GUARD version
  LOOKUP billing_preference_id BY billing_preference_id
  ARG billing_preference_id STRING REQUIRED MAX LENGTH 36 DESCRIPTION 'Reviewed billing-preference UUID returned by Explore or inspection.'
  ARG enabled BOOLEAN REQUIRED DESCRIPTION 'True to enable autopay; false to disable it.'
  ALLOW READ billing_preference_id, account_id, autopay_enabled, paperless_billing, monthly_spend_alert_cents, payment_method_label, version, updated_at
  MODEL WITHHELD account_id
  REQUIRE EVIDENCE
  MAX ROWS 1
  PROPOSE ACTION billing.propose_autopay_change UPDATE
  ALLOW WRITE autopay_enabled
  PATCH autopay_enabled = ARG enabled
  APPROVAL ROLE support_supervisor
  WRITEBACK APP HANDLER EXECUTOR telecom_app_handler
END

CREATE CAPABILITY billing.propose_paperless_change
  DESCRIPTION 'Propose enabling or disabling paperless billing for the authenticated account owner or manager.'
  RETURNS HINT 'Returns a review-required proposal id and exact diff; the source database is unchanged until external approval and app-owned apply.'
  USING CONTEXT telecom_customer
  SOURCE telecom_postgres
  ON telecom.billing_preferences
  PRIMARY KEY billing_preference_id
  TENANT KEY account_id
  CONFLICT GUARD version
  LOOKUP billing_preference_id BY billing_preference_id
  ARG billing_preference_id STRING REQUIRED MAX LENGTH 36 DESCRIPTION 'Reviewed billing-preference UUID returned by Explore or inspection.'
  ARG enabled BOOLEAN REQUIRED DESCRIPTION 'True for paperless billing; false for paper statements.'
  ALLOW READ billing_preference_id, account_id, autopay_enabled, paperless_billing, monthly_spend_alert_cents, payment_method_label, version, updated_at
  MODEL WITHHELD account_id
  REQUIRE EVIDENCE
  MAX ROWS 1
  PROPOSE ACTION billing.propose_paperless_change UPDATE
  ALLOW WRITE paperless_billing
  PATCH paperless_billing = ARG enabled
  APPROVAL ROLE support_supervisor
  WRITEBACK APP HANDLER EXECUTOR telecom_app_handler
END

CREATE CAPABILITY billing.propose_spend_alert_change
  DESCRIPTION 'Propose a monthly account-spend notification threshold. Thresholds up to 25000 cents may be policy-approved within tenant daily circuit breakers.'
  RETURNS HINT 'Returns a proposal id and exact diff. A qualifying low-risk threshold may be auto-approved, but source writeback remains a separate trusted operation.'
  USING CONTEXT telecom_customer
  SOURCE telecom_postgres
  ON telecom.billing_preferences
  PRIMARY KEY billing_preference_id
  TENANT KEY account_id
  CONFLICT GUARD version
  LOOKUP billing_preference_id BY billing_preference_id
  ARG billing_preference_id STRING REQUIRED MAX LENGTH 36 DESCRIPTION 'Reviewed billing-preference UUID returned by Explore or inspection.'
  ARG threshold_cents NUMBER REQUIRED MIN 1000 MAX 50000 DESCRIPTION 'Monthly spend alert threshold in cents, from 1000 through 50000.'
  ALLOW READ billing_preference_id, account_id, monthly_spend_alert_cents, version, updated_at
  MODEL WITHHELD account_id
  REQUIRE EVIDENCE
  MAX ROWS 1
  PROPOSE ACTION billing.propose_spend_alert_change UPDATE
  ALLOW WRITE monthly_spend_alert_cents
  PATCH monthly_spend_alert_cents = ARG threshold_cents
  BOUND monthly_spend_alert_cents 1000..50000
  APPROVAL ROLE support_supervisor
  AUTO APPROVE WHEN monthly_spend_alert_cents <= 25000
  LIMIT 10 PER DAY
  LIMIT TOTAL 100000 PER DAY
  WRITEBACK APP HANDLER EXECUTOR telecom_app_handler
END

-- ============================ Helpdesk cases ==========================

CREATE CAPABILITY support.inspect_case
  DESCRIPTION 'Inspect one customer-visible support case before reporting details or proposing a customer note.'
  RETURNS HINT 'Returns the reviewed case number, issue details, current status, latest support update, latest customer note, note count, row version, and evidence handle.'
  USING CONTEXT telecom_customer
  SOURCE telecom_postgres
  ON telecom.support_cases
  PRIMARY KEY case_id
  TENANT KEY account_id
  LOOKUP case_id BY case_id
  ARG case_id STRING REQUIRED MAX LENGTH 36 DESCRIPTION 'Reviewed support-case UUID returned by Explore.'
  ALLOW READ case_id, account_id, case_number, category, subject, description, status, priority, latest_update_summary, latest_customer_note, latest_customer_note_length, customer_note_count, created_at, updated_at, version
  MODEL WITHHELD account_id
  KEEP OUT opened_by_principal_id, assigned_agent_id, note_policy_units
  REQUIRE EVIDENCE
  MAX ROWS 1
END

CREATE CAPABILITY support.propose_case_note
  DESCRIPTION 'Propose adding a customer-authored note to one visible, non-closed support case. Notes up to 1000 characters may be policy-approved within tenant daily circuit breakers.'
  RETURNS HINT 'Returns a proposal id and exact note diff. A bounded note may be policy-approved, but insertion into case history remains a separate trusted app-owned operation.'
  USING CONTEXT telecom_customer
  SOURCE telecom_postgres
  ON telecom.support_cases
  PRIMARY KEY case_id
  TENANT KEY account_id
  CONFLICT GUARD version
  LOOKUP case_id BY case_id
  ARG case_id STRING REQUIRED MAX LENGTH 36 DESCRIPTION 'Reviewed support-case UUID returned by Explore or exact case inspection.'
  ARG note TEXT REQUIRED MAX LENGTH 1000 DESCRIPTION 'Exact customer-authored note to append to the support case.'
  ALLOW READ case_id, account_id, case_number, category, subject, status, priority, latest_update_summary, latest_customer_note, latest_customer_note_length, customer_note_count, created_at, updated_at, version
  MODEL WITHHELD account_id
  KEEP OUT opened_by_principal_id, assigned_agent_id, note_policy_units
  REQUIRE EVIDENCE
  MAX ROWS 1
  PROPOSE ACTION support.propose_case_note UPDATE
  ALLOW WRITE latest_customer_note, note_policy_units
  PATCH latest_customer_note = ARG note
  PATCH note_policy_units = 1
  BOUND note_policy_units 1..1
  APPROVAL ROLE support_supervisor
  AUTO APPROVE WHEN note_policy_units <= 1
  LIMIT 20 PER DAY
  WRITEBACK APP HANDLER EXECUTOR telecom_app_handler
END
