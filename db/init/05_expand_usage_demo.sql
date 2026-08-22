\set ON_ERROR_STOP on

-- This migration is idempotent so it can enrich both a fresh demo database and
-- the already-running tutorial database without deleting existing data.
INSERT INTO telecom.usage_daily (
  account_id, line_id, usage_date, data_mb, voice_minutes, sms_count, roaming_data_mb
)
SELECT l.account_id,
       l.line_id,
       d::date,
       120 + abs(hashtext(l.line_id::text || d::text)) % 2100,
       2 + abs(hashtext('voice' || l.line_id::text || d::text)) % 95,
       abs(hashtext('sms' || l.line_id::text || d::text)) % 60,
       CASE
         WHEN l.international_roaming_enabled AND extract(day from d)::int % 17 IN (0, 1)
           THEN 20 + abs(hashtext('roam' || l.line_id::text || d::text)) % 300
         ELSE 0
       END
FROM telecom.service_lines l
CROSS JOIN generate_series(current_date - 364, current_date, interval '1 day') d
ON CONFLICT (account_id, line_id, usage_date) DO NOTHING;

INSERT INTO telecom.invoices (
  invoice_id, account_id, invoice_number, period_start, period_end, due_date,
  subtotal_cents, taxes_cents, adjustments_cents, total_cents, balance_cents, status, created_at
)
SELECT md5('invoice-' || a.account_number || '-' || month_offset::text)::uuid,
       a.account_id,
       a.account_number || '-' || to_char(current_date - (month_offset || ' month')::interval, 'YYYYMM'),
       (date_trunc('month', current_date - (month_offset || ' month')::interval) - interval '1 month')::date,
       (date_trunc('month', current_date - (month_offset || ' month')::interval) - interval '1 day')::date,
       (date_trunc('month', current_date - (month_offset || ' month')::interval) + interval '14 days')::date,
       s.base_monthly_cents + (abs(hashtext(a.account_number || month_offset::text)) % 2200),
       700 + (abs(hashtext('tax' || a.account_number || month_offset::text)) % 1400),
       CASE WHEN month_offset = 5 THEN -500 ELSE 0 END,
       s.base_monthly_cents + (abs(hashtext(a.account_number || month_offset::text)) % 2200)
         + 700 + (abs(hashtext('tax' || a.account_number || month_offset::text)) % 1400)
         + CASE WHEN month_offset = 5 THEN -500 ELSE 0 END,
       0,
       'paid'::telecom.invoice_status,
       date_trunc('month', current_date - (month_offset || ' month')::interval)
FROM telecom.accounts a
JOIN telecom.subscriptions s ON s.account_id = a.account_id
CROSS JOIN generate_series(12, 23) month_offset
ON CONFLICT (invoice_number) DO NOTHING;

INSERT INTO telecom.payments (
  payment_id, account_id, invoice_id, paid_at, amount_cents, method_label, status, confirmation_code
)
SELECT md5('payment-' || i.invoice_number)::uuid, i.account_id, i.invoice_id,
       i.due_date::timestamptz - interval '3 days', i.total_cents,
       CASE WHEN abs(hashtext(i.account_id::text)) % 2 = 0
         THEN 'Visa ending 8842' ELSE 'Bank account ending 3110' END,
       'settled', 'CONF-' || upper(substr(md5(i.invoice_number), 1, 12))
FROM telecom.invoices i
WHERE i.status = 'paid'
ON CONFLICT (payment_id) DO NOTHING;

ALTER TABLE customer_explore.usage_daily
  ADD COLUMN IF NOT EXISTS subscriber_name text,
  ADD COLUMN IF NOT EXISTS relationship_label text,
  ADD COLUMN IF NOT EXISTS line_label text,
  ADD COLUMN IF NOT EXISTS device_name text;

INSERT INTO customer_explore.usage_daily (
  explore_row_id, account_id, viewer_principal_id, usage_id, line_id, usage_date,
  data_mb, voice_minutes, sms_count, roaming_data_mb,
  subscriber_name, relationship_label, line_label, device_name
)
SELECT md5(m.principal_id::text || ':' || u.usage_id::text)::uuid,
       u.account_id, m.principal_id, u.usage_id, u.line_id, u.usage_date,
       u.data_mb, u.voice_minutes, u.sms_count, u.roaming_data_mb,
       s.display_name, s.relationship_label, l.line_label, l.device_name
FROM telecom.usage_daily u
JOIN telecom.service_lines l
  ON l.account_id = u.account_id AND l.line_id = u.line_id
JOIN telecom.subscribers s
  ON s.account_id = l.account_id AND s.subscriber_id = l.subscriber_id
JOIN telecom.account_memberships m ON m.account_id = u.account_id
WHERE m.status = 'active'
  AND (m.membership_role IN ('owner', 'manager') OR m.subscriber_id = l.subscriber_id)
ON CONFLICT (account_id, viewer_principal_id, usage_id) DO UPDATE
SET subscriber_name = EXCLUDED.subscriber_name,
    relationship_label = EXCLUDED.relationship_label,
    line_label = EXCLUDED.line_label,
    device_name = EXCLUDED.device_name;

ALTER TABLE customer_explore.usage_daily
  ALTER COLUMN subscriber_name SET NOT NULL,
  ALTER COLUMN relationship_label SET NOT NULL,
  ALTER COLUMN line_label SET NOT NULL,
  ALTER COLUMN device_name SET NOT NULL;

INSERT INTO customer_explore.invoices
SELECT md5(m.principal_id::text || ':' || i.invoice_id::text)::uuid,
       i.account_id, m.principal_id, i.invoice_id, i.period_start, i.period_end,
       i.due_date, i.status, i.subtotal_cents, i.taxes_cents,
       i.adjustments_cents, i.total_cents, i.balance_cents, i.created_at, i.updated_at
FROM telecom.invoices i
JOIN telecom.account_memberships m USING (account_id)
WHERE m.status = 'active' AND m.membership_role IN ('owner', 'manager')
ON CONFLICT (account_id, viewer_principal_id, invoice_id) DO NOTHING;

INSERT INTO customer_explore.payments
SELECT md5(m.principal_id::text || ':' || p.payment_id::text)::uuid,
       p.account_id, m.principal_id, p.payment_id, p.invoice_id, p.paid_at,
       p.amount_cents, p.status
FROM telecom.payments p
JOIN telecom.account_memberships m USING (account_id)
WHERE m.status = 'active' AND m.membership_role IN ('owner', 'manager')
ON CONFLICT (account_id, viewer_principal_id, payment_id) DO NOTHING;

CREATE INDEX IF NOT EXISTS explore_usage_member_date_idx
  ON customer_explore.usage_daily (
    account_id, viewer_principal_id, subscriber_name, usage_date DESC
  );

GRANT SELECT ON customer_explore.usage_daily TO synapsor_explore_reader;
