\set ON_ERROR_STOP on

SET ROLE telecom_owner;

CREATE SCHEMA customer_explore AUTHORIZATION telecom_owner;

CREATE TABLE customer_explore.accounts (
  explore_row_id uuid PRIMARY KEY,
  account_id uuid NOT NULL,
  viewer_principal_id uuid NOT NULL,
  account_name text NOT NULL,
  account_kind telecom.account_kind NOT NULL,
  status telecom.record_status NOT NULL,
  billing_cycle_day smallint NOT NULL,
  country_code char(2) NOT NULL,
  currency_code char(3) NOT NULL,
  created_at timestamptz NOT NULL,
  UNIQUE (account_id, viewer_principal_id)
);

CREATE TABLE customer_explore.subscriptions (
  explore_row_id uuid PRIMARY KEY,
  account_id uuid NOT NULL,
  viewer_principal_id uuid NOT NULL,
  subscription_id uuid NOT NULL,
  plan_code telecom.plan_code NOT NULL,
  plan_display_name text NOT NULL,
  base_monthly_cents integer NOT NULL,
  included_lines smallint NOT NULL,
  data_policy text NOT NULL,
  international_day_pass boolean NOT NULL,
  effective_from date NOT NULL,
  contract_end_date date,
  updated_at timestamptz NOT NULL,
  version bigint NOT NULL,
  UNIQUE (account_id, viewer_principal_id, subscription_id)
);

CREATE TABLE customer_explore.subscribers (
  explore_row_id uuid PRIMARY KEY,
  account_id uuid NOT NULL,
  viewer_principal_id uuid NOT NULL,
  subscriber_id uuid NOT NULL,
  display_name text NOT NULL,
  relationship_label text NOT NULL,
  status telecom.record_status NOT NULL,
  created_at timestamptz NOT NULL,
  UNIQUE (account_id, viewer_principal_id, subscriber_id)
);

CREATE TABLE customer_explore.service_lines (
  explore_row_id uuid PRIMARY KEY,
  account_id uuid NOT NULL,
  viewer_principal_id uuid NOT NULL,
  line_id uuid NOT NULL,
  subscriber_id uuid NOT NULL,
  line_label text NOT NULL,
  phone_last4 char(4) NOT NULL,
  status telecom.line_status NOT NULL,
  device_name text NOT NULL,
  international_roaming_enabled boolean NOT NULL,
  data_limit_gb numeric(8,2),
  activated_on date NOT NULL,
  updated_at timestamptz NOT NULL,
  version bigint NOT NULL,
  UNIQUE (account_id, viewer_principal_id, line_id)
);

CREATE TABLE customer_explore.usage_daily (
  explore_row_id uuid PRIMARY KEY,
  account_id uuid NOT NULL,
  viewer_principal_id uuid NOT NULL,
  usage_id bigint NOT NULL,
  line_id uuid NOT NULL,
  usage_date date NOT NULL,
  data_mb integer NOT NULL,
  voice_minutes integer NOT NULL,
  sms_count integer NOT NULL,
  roaming_data_mb integer NOT NULL,
  UNIQUE (account_id, viewer_principal_id, usage_id)
);

CREATE TABLE customer_explore.invoices (
  explore_row_id uuid PRIMARY KEY,
  account_id uuid NOT NULL,
  viewer_principal_id uuid NOT NULL,
  invoice_id uuid NOT NULL,
  period_start date NOT NULL,
  period_end date NOT NULL,
  due_date date NOT NULL,
  status telecom.invoice_status NOT NULL,
  subtotal_cents integer NOT NULL,
  taxes_cents integer NOT NULL,
  adjustments_cents integer NOT NULL,
  total_cents integer NOT NULL,
  balance_cents integer NOT NULL,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  UNIQUE (account_id, viewer_principal_id, invoice_id)
);

CREATE TABLE customer_explore.payments (
  explore_row_id uuid PRIMARY KEY,
  account_id uuid NOT NULL,
  viewer_principal_id uuid NOT NULL,
  payment_id uuid NOT NULL,
  invoice_id uuid NOT NULL,
  paid_at timestamptz NOT NULL,
  amount_cents integer NOT NULL,
  status telecom.payment_status NOT NULL,
  UNIQUE (account_id, viewer_principal_id, payment_id)
);

CREATE TABLE customer_explore.billing_preferences (
  explore_row_id uuid PRIMARY KEY,
  account_id uuid NOT NULL,
  viewer_principal_id uuid NOT NULL,
  billing_preference_id uuid NOT NULL,
  autopay_enabled boolean NOT NULL,
  paperless_billing boolean NOT NULL,
  monthly_spend_alert_cents integer NOT NULL,
  updated_at timestamptz NOT NULL,
  version bigint NOT NULL,
  UNIQUE (account_id, viewer_principal_id, billing_preference_id)
);

CREATE TABLE customer_explore.support_cases (
  explore_row_id uuid PRIMARY KEY,
  account_id uuid NOT NULL,
  viewer_principal_id uuid NOT NULL,
  case_id uuid NOT NULL,
  subject text NOT NULL,
  status text NOT NULL,
  priority text NOT NULL,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  UNIQUE (account_id, viewer_principal_id, case_id)
);

RESET ROLE;

INSERT INTO customer_explore.accounts
SELECT md5(m.principal_id::text || ':' || a.account_id::text)::uuid,
       a.account_id, m.principal_id, a.account_name, a.account_kind, a.status,
       a.billing_cycle_day, a.country_code, a.currency_code, a.created_at
FROM telecom.accounts a
JOIN telecom.account_memberships m USING (account_id)
WHERE m.status = 'active';

INSERT INTO customer_explore.subscriptions
SELECT md5(m.principal_id::text || ':' || s.subscription_id::text)::uuid,
       s.account_id, m.principal_id, s.subscription_id, s.plan_code,
       s.plan_display_name, s.base_monthly_cents, s.included_lines, s.data_policy,
       s.international_day_pass, s.effective_from, s.contract_end_date,
       s.updated_at, s.version
FROM telecom.subscriptions s
JOIN telecom.account_memberships m USING (account_id)
WHERE m.status = 'active';

INSERT INTO customer_explore.subscribers
SELECT md5(m.principal_id::text || ':' || s.subscriber_id::text)::uuid,
       s.account_id, m.principal_id, s.subscriber_id, s.display_name,
       s.relationship_label, s.status, s.created_at
FROM telecom.subscribers s
JOIN telecom.account_memberships m USING (account_id)
WHERE m.status = 'active'
  AND (m.membership_role IN ('owner', 'manager') OR m.subscriber_id = s.subscriber_id);

INSERT INTO customer_explore.service_lines
SELECT md5(m.principal_id::text || ':' || l.line_id::text)::uuid,
       l.account_id, m.principal_id, l.line_id, l.subscriber_id, l.line_label,
       l.phone_last4, l.status, l.device_name, l.international_roaming_enabled,
       l.data_limit_gb, l.activated_on, l.updated_at, l.version
FROM telecom.service_lines l
JOIN telecom.account_memberships m USING (account_id)
WHERE m.status = 'active'
  AND (m.membership_role IN ('owner', 'manager') OR m.subscriber_id = l.subscriber_id);

INSERT INTO customer_explore.usage_daily
SELECT md5(m.principal_id::text || ':' || u.usage_id::text)::uuid,
       u.account_id, m.principal_id, u.usage_id, u.line_id, u.usage_date,
       u.data_mb, u.voice_minutes, u.sms_count, u.roaming_data_mb
FROM telecom.usage_daily u
JOIN telecom.service_lines l ON l.account_id = u.account_id AND l.line_id = u.line_id
JOIN telecom.account_memberships m ON m.account_id = u.account_id
WHERE m.status = 'active'
  AND (m.membership_role IN ('owner', 'manager') OR m.subscriber_id = l.subscriber_id);

INSERT INTO customer_explore.invoices
SELECT md5(m.principal_id::text || ':' || i.invoice_id::text)::uuid,
       i.account_id, m.principal_id, i.invoice_id, i.period_start, i.period_end,
       i.due_date, i.status, i.subtotal_cents, i.taxes_cents,
       i.adjustments_cents, i.total_cents, i.balance_cents, i.created_at, i.updated_at
FROM telecom.invoices i
JOIN telecom.account_memberships m USING (account_id)
WHERE m.status = 'active' AND m.membership_role IN ('owner', 'manager');

INSERT INTO customer_explore.payments
SELECT md5(m.principal_id::text || ':' || p.payment_id::text)::uuid,
       p.account_id, m.principal_id, p.payment_id, p.invoice_id, p.paid_at,
       p.amount_cents, p.status
FROM telecom.payments p
JOIN telecom.account_memberships m USING (account_id)
WHERE m.status = 'active' AND m.membership_role IN ('owner', 'manager');

INSERT INTO customer_explore.billing_preferences
SELECT md5(m.principal_id::text || ':' || b.billing_preference_id::text)::uuid,
       b.account_id, m.principal_id, b.billing_preference_id, b.autopay_enabled,
       b.paperless_billing, b.monthly_spend_alert_cents, b.updated_at, b.version
FROM telecom.billing_preferences b
JOIN telecom.account_memberships m USING (account_id)
WHERE m.status = 'active' AND m.membership_role IN ('owner', 'manager');

INSERT INTO customer_explore.support_cases
SELECT md5(m.principal_id::text || ':' || c.case_id::text)::uuid,
       c.account_id, m.principal_id, c.case_id, c.subject, c.status, c.priority,
       c.created_at, c.updated_at
FROM telecom.support_cases c
JOIN telecom.account_memberships m USING (account_id)
WHERE m.status = 'active'
  AND (m.membership_role IN ('owner', 'manager') OR c.opened_by_principal_id = m.principal_id);

SET ROLE telecom_owner;

CREATE INDEX explore_accounts_scope_idx ON customer_explore.accounts(account_id, viewer_principal_id);
CREATE INDEX explore_subscriptions_scope_idx ON customer_explore.subscriptions(account_id, viewer_principal_id);
CREATE INDEX explore_subscribers_scope_idx ON customer_explore.subscribers(account_id, viewer_principal_id);
CREATE INDEX explore_lines_scope_idx ON customer_explore.service_lines(account_id, viewer_principal_id);
CREATE INDEX explore_usage_scope_date_idx ON customer_explore.usage_daily(account_id, viewer_principal_id, usage_date DESC);
CREATE INDEX explore_invoices_scope_period_idx ON customer_explore.invoices(account_id, viewer_principal_id, period_end DESC);
CREATE INDEX explore_payments_scope_idx ON customer_explore.payments(account_id, viewer_principal_id);
CREATE INDEX explore_billing_scope_idx ON customer_explore.billing_preferences(account_id, viewer_principal_id);
CREATE INDEX explore_cases_scope_idx ON customer_explore.support_cases(account_id, viewer_principal_id, updated_at DESC);

GRANT USAGE ON SCHEMA customer_explore TO synapsor_explore_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA customer_explore TO synapsor_explore_reader;

CREATE FUNCTION telecom.sync_subscription_projection(p_account_id uuid, p_subscription_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, telecom, customer_explore AS $$
BEGIN
  IF p_account_id IS DISTINCT FROM nullif(current_setting('synapsor.tenant_id', true), '')::uuid
     OR NOT telecom.can_manage_account(p_account_id, nullif(current_setting('synapsor.principal', true), '')::uuid) THEN
    RAISE EXCEPTION 'scope denied';
  END IF;
  UPDATE customer_explore.subscriptions e
  SET plan_code = s.plan_code, plan_display_name = s.plan_display_name,
      base_monthly_cents = s.base_monthly_cents, included_lines = s.included_lines,
      data_policy = s.data_policy, international_day_pass = s.international_day_pass,
      effective_from = s.effective_from, contract_end_date = s.contract_end_date,
      updated_at = s.updated_at, version = s.version
  FROM telecom.subscriptions s
  WHERE s.account_id = p_account_id AND s.subscription_id = p_subscription_id
    AND e.account_id = s.account_id AND e.subscription_id = s.subscription_id;
END $$;

CREATE FUNCTION telecom.sync_line_projection(p_account_id uuid, p_line_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, telecom, customer_explore AS $$
BEGIN
  IF p_account_id IS DISTINCT FROM nullif(current_setting('synapsor.tenant_id', true), '')::uuid
     OR NOT telecom.can_view_line(p_account_id, p_line_id, nullif(current_setting('synapsor.principal', true), '')::uuid) THEN
    RAISE EXCEPTION 'scope denied';
  END IF;
  UPDATE customer_explore.service_lines e
  SET international_roaming_enabled = l.international_roaming_enabled,
      updated_at = l.updated_at, version = l.version
  FROM telecom.service_lines l
  WHERE l.account_id = p_account_id AND l.line_id = p_line_id
    AND e.account_id = l.account_id AND e.line_id = l.line_id;
END $$;

CREATE FUNCTION telecom.sync_billing_projection(p_account_id uuid, p_billing_preference_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, telecom, customer_explore AS $$
BEGIN
  IF p_account_id IS DISTINCT FROM nullif(current_setting('synapsor.tenant_id', true), '')::uuid
     OR NOT telecom.can_manage_account(p_account_id, nullif(current_setting('synapsor.principal', true), '')::uuid) THEN
    RAISE EXCEPTION 'scope denied';
  END IF;
  UPDATE customer_explore.billing_preferences e
  SET autopay_enabled = b.autopay_enabled, paperless_billing = b.paperless_billing,
      monthly_spend_alert_cents = b.monthly_spend_alert_cents,
      updated_at = b.updated_at, version = b.version
  FROM telecom.billing_preferences b
  WHERE b.account_id = p_account_id AND b.billing_preference_id = p_billing_preference_id
    AND e.account_id = b.account_id AND e.billing_preference_id = b.billing_preference_id;
END $$;

REVOKE ALL ON FUNCTION telecom.sync_subscription_projection(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION telecom.sync_line_projection(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION telecom.sync_billing_projection(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION telecom.sync_subscription_projection(uuid, uuid) TO synapsor_writer;
GRANT EXECUTE ON FUNCTION telecom.sync_line_projection(uuid, uuid) TO synapsor_writer;
GRANT EXECUTE ON FUNCTION telecom.sync_billing_projection(uuid, uuid) TO synapsor_writer;

RESET ROLE;
