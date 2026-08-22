\set ON_ERROR_STOP on
RESET ROLE;

CREATE OR REPLACE FUNCTION telecom.seed_uuid(seed text)
RETURNS uuid
LANGUAGE sql
IMMUTABLE
STRICT
AS $$
  SELECT (
    substr(md5(seed), 1, 8) || '-' ||
    substr(md5(seed), 9, 4) || '-' ||
    substr(md5(seed), 13, 4) || '-' ||
    substr(md5(seed), 17, 4) || '-' ||
    substr(md5(seed), 21, 12)
  )::uuid
$$;

INSERT INTO telecom.accounts (
  account_id, account_number, account_name, account_kind,
  billing_cycle_day, country_code, currency_code, created_at
)
VALUES
  (telecom.seed_uuid('account-atlas'), 'US-100001', 'Atlas Family', 'family', 12, 'US', 'USD', now() - interval '4 years'),
  (telecom.seed_uuid('account-meridian'), 'US-100002', 'Meridian Family', 'family', 18, 'US', 'USD', now() - interval '3 years'),
  (telecom.seed_uuid('account-chen'), 'US-100003', 'Eli Chen', 'individual', 5, 'US', 'USD', now() - interval '2 years'),
  (telecom.seed_uuid('account-nguyen'), 'US-100004', 'Sophia Nguyen', 'individual', 23, 'US', 'USD', now() - interval '18 months'),
  (telecom.seed_uuid('account-horizon'), 'CA-200001', 'Horizon Household', 'family', 9, 'CA', 'CAD', now() - interval '5 years'),
  (telecom.seed_uuid('account-summit'), 'GB-300001', 'Summit Design', 'business', 15, 'GB', 'GBP', now() - interval '6 years');

INSERT INTO telecom.principals (principal_id, email, display_name, password_hash, locale)
VALUES
  (telecom.seed_uuid('principal-alex'), 'alex.atlas@example.test', 'Alex Atlas', public.crypt('demo123!', public.gen_salt('bf')), 'en-US'),
  (telecom.seed_uuid('principal-jamie'), 'jamie.atlas@example.test', 'Jamie Atlas', public.crypt('demo123!', public.gen_salt('bf')), 'en-US'),
  (telecom.seed_uuid('principal-maya'), 'maya.atlas@example.test', 'Maya Atlas', public.crypt('demo123!', public.gen_salt('bf')), 'en-US'),
  (telecom.seed_uuid('principal-noah'), 'noah.atlas@example.test', 'Noah Atlas', public.crypt('demo123!', public.gen_salt('bf')), 'en-US'),
  (telecom.seed_uuid('principal-priya'), 'priya.meridian@example.test', 'Priya Rao', public.crypt('demo123!', public.gen_salt('bf')), 'en-US'),
  (telecom.seed_uuid('principal-arjun'), 'arjun.meridian@example.test', 'Arjun Rao', public.crypt('demo123!', public.gen_salt('bf')), 'en-US'),
  (telecom.seed_uuid('principal-leena'), 'leena.meridian@example.test', 'Leena Rao', public.crypt('demo123!', public.gen_salt('bf')), 'en-US'),
  (telecom.seed_uuid('principal-eli'), 'eli.chen@example.test', 'Eli Chen', public.crypt('demo123!', public.gen_salt('bf')), 'en-US'),
  (telecom.seed_uuid('principal-sophia'), 'sophia.nguyen@example.test', 'Sophia Nguyen', public.crypt('demo123!', public.gen_salt('bf')), 'en-US'),
  (telecom.seed_uuid('principal-amelie'), 'amelie.horizon@example.test', 'Amelie Laurent', public.crypt('demo123!', public.gen_salt('bf')), 'fr-CA'),
  (telecom.seed_uuid('principal-luc'), 'luc.horizon@example.test', 'Luc Laurent', public.crypt('demo123!', public.gen_salt('bf')), 'fr-CA'),
  (telecom.seed_uuid('principal-ava'), 'ava.summit@example.test', 'Ava Morgan', public.crypt('demo123!', public.gen_salt('bf')), 'en-GB'),
  (telecom.seed_uuid('principal-ben'), 'ben.summit@example.test', 'Ben Hughes', public.crypt('demo123!', public.gen_salt('bf')), 'en-GB'),
  (telecom.seed_uuid('principal-agent-1'), 'agent.lee@example.test', 'Jordan Lee', public.crypt('agent-demo!', public.gen_salt('bf')), 'en-US'),
  (telecom.seed_uuid('principal-agent-2'), 'agent.singh@example.test', 'Kiran Singh', public.crypt('agent-demo!', public.gen_salt('bf')), 'en-GB');

INSERT INTO telecom.subscribers (
  subscriber_id, account_id, principal_id, display_name, relationship_label, access_level, created_at
)
VALUES
  (telecom.seed_uuid('subscriber-alex'), telecom.seed_uuid('account-atlas'), telecom.seed_uuid('principal-alex'), 'Alex Atlas', 'Plan owner', 'household', now() - interval '4 years'),
  (telecom.seed_uuid('subscriber-jamie'), telecom.seed_uuid('account-atlas'), telecom.seed_uuid('principal-jamie'), 'Jamie Atlas', 'Spouse', 'household', now() - interval '4 years'),
  (telecom.seed_uuid('subscriber-maya'), telecom.seed_uuid('account-atlas'), telecom.seed_uuid('principal-maya'), 'Maya Atlas', 'Daughter', 'self', now() - interval '3 years'),
  (telecom.seed_uuid('subscriber-noah'), telecom.seed_uuid('account-atlas'), telecom.seed_uuid('principal-noah'), 'Noah Atlas', 'Son', 'self', now() - interval '2 years'),
  (telecom.seed_uuid('subscriber-priya'), telecom.seed_uuid('account-meridian'), telecom.seed_uuid('principal-priya'), 'Priya Rao', 'Plan owner', 'household', now() - interval '3 years'),
  (telecom.seed_uuid('subscriber-arjun'), telecom.seed_uuid('account-meridian'), telecom.seed_uuid('principal-arjun'), 'Arjun Rao', 'Spouse', 'household', now() - interval '3 years'),
  (telecom.seed_uuid('subscriber-leena'), telecom.seed_uuid('account-meridian'), telecom.seed_uuid('principal-leena'), 'Leena Rao', 'Daughter', 'self', now() - interval '1 year'),
  (telecom.seed_uuid('subscriber-eli'), telecom.seed_uuid('account-chen'), telecom.seed_uuid('principal-eli'), 'Eli Chen', 'Plan owner', 'household', now() - interval '2 years'),
  (telecom.seed_uuid('subscriber-sophia'), telecom.seed_uuid('account-nguyen'), telecom.seed_uuid('principal-sophia'), 'Sophia Nguyen', 'Plan owner', 'household', now() - interval '18 months'),
  (telecom.seed_uuid('subscriber-amelie'), telecom.seed_uuid('account-horizon'), telecom.seed_uuid('principal-amelie'), 'Amelie Laurent', 'Plan owner', 'household', now() - interval '5 years'),
  (telecom.seed_uuid('subscriber-luc'), telecom.seed_uuid('account-horizon'), telecom.seed_uuid('principal-luc'), 'Luc Laurent', 'Spouse', 'self', now() - interval '4 years'),
  (telecom.seed_uuid('subscriber-ava'), telecom.seed_uuid('account-summit'), telecom.seed_uuid('principal-ava'), 'Ava Morgan', 'Account admin', 'household', now() - interval '6 years'),
  (telecom.seed_uuid('subscriber-ben'), telecom.seed_uuid('account-summit'), telecom.seed_uuid('principal-ben'), 'Ben Hughes', 'Employee', 'self', now() - interval '2 years');

INSERT INTO telecom.account_memberships (
  membership_id, account_id, principal_id, subscriber_id, membership_role, joined_at
)
SELECT telecom.seed_uuid('membership-' || p.email), s.account_id, p.principal_id, s.subscriber_id,
       CASE
         WHEN p.email IN ('alex.atlas@example.test', 'priya.meridian@example.test', 'eli.chen@example.test',
                          'sophia.nguyen@example.test', 'amelie.horizon@example.test', 'ava.summit@example.test')
           THEN 'owner'::telecom.membership_role
         WHEN p.email IN ('jamie.atlas@example.test', 'arjun.meridian@example.test')
           THEN 'manager'::telecom.membership_role
         ELSE 'member'::telecom.membership_role
       END,
       s.created_at
FROM telecom.principals p
JOIN telecom.subscribers s ON s.principal_id = p.principal_id;

INSERT INTO telecom.subscriptions (
  subscription_id, account_id, plan_code, plan_display_name, base_monthly_cents,
  included_lines, data_policy, international_day_pass, effective_from, contract_end_date
)
VALUES
  (telecom.seed_uuid('subscription-atlas'), telecom.seed_uuid('account-atlas'), 'family_premium', 'Family Premium', 16500, 4, 'Unlimited premium data; 60 GB hotspot per line', true, current_date - 420, NULL),
  (telecom.seed_uuid('subscription-meridian'), telecom.seed_uuid('account-meridian'), 'unlimited_plus', 'Unlimited Plus', 13500, 3, 'Unlimited data; 30 GB hotspot per line', false, current_date - 310, NULL),
  (telecom.seed_uuid('subscription-chen'), telecom.seed_uuid('account-chen'), 'unlimited', 'Unlimited', 6500, 1, 'Unlimited data; speeds may slow after 75 GB', false, current_date - 220, NULL),
  (telecom.seed_uuid('subscription-nguyen'), telecom.seed_uuid('account-nguyen'), 'starter', 'Starter 15 GB', 4500, 1, '15 GB high-speed data', false, current_date - 180, current_date + 185),
  (telecom.seed_uuid('subscription-horizon'), telecom.seed_uuid('account-horizon'), 'family_premium', 'Family Premium', 20500, 4, 'Unlimited premium data; Canada/US roaming included', true, current_date - 510, NULL),
  (telecom.seed_uuid('subscription-summit'), telecom.seed_uuid('account-summit'), 'unlimited_plus', 'Business Unlimited Plus', 12000, 2, 'Unlimited priority business data', true, current_date - 600, current_date + 365);

INSERT INTO telecom.service_lines (
  line_id, account_id, subscriber_id, line_label, phone_last4, device_name,
  esim, international_roaming_enabled, data_limit_gb, activated_on
)
VALUES
  (telecom.seed_uuid('line-alex'), telecom.seed_uuid('account-atlas'), telecom.seed_uuid('subscriber-alex'), 'Alex primary', '4101', 'iPhone 17 Pro', true, true, NULL, current_date - 900),
  (telecom.seed_uuid('line-jamie'), telecom.seed_uuid('account-atlas'), telecom.seed_uuid('subscriber-jamie'), 'Jamie primary', '4102', 'Pixel 11', true, true, NULL, current_date - 850),
  (telecom.seed_uuid('line-maya'), telecom.seed_uuid('account-atlas'), telecom.seed_uuid('subscriber-maya'), 'Maya phone', '4103', 'iPhone 16', true, false, 35, current_date - 600),
  (telecom.seed_uuid('line-noah'), telecom.seed_uuid('account-atlas'), telecom.seed_uuid('subscriber-noah'), 'Noah phone', '4104', 'Galaxy S27', true, false, 25, current_date - 420),
  (telecom.seed_uuid('line-priya'), telecom.seed_uuid('account-meridian'), telecom.seed_uuid('subscriber-priya'), 'Priya phone', '5201', 'iPhone 17', true, false, NULL, current_date - 700),
  (telecom.seed_uuid('line-arjun'), telecom.seed_uuid('account-meridian'), telecom.seed_uuid('subscriber-arjun'), 'Arjun phone', '5202', 'Pixel 10 Pro', true, false, NULL, current_date - 690),
  (telecom.seed_uuid('line-leena'), telecom.seed_uuid('account-meridian'), telecom.seed_uuid('subscriber-leena'), 'Leena phone', '5203', 'Galaxy A58', true, false, 20, current_date - 300),
  (telecom.seed_uuid('line-eli'), telecom.seed_uuid('account-chen'), telecom.seed_uuid('subscriber-eli'), 'Personal line', '6301', 'Pixel 11 Pro', true, true, NULL, current_date - 500),
  (telecom.seed_uuid('line-sophia'), telecom.seed_uuid('account-nguyen'), telecom.seed_uuid('subscriber-sophia'), 'Personal line', '6401', 'iPhone 16e', true, false, 15, current_date - 420),
  (telecom.seed_uuid('line-amelie'), telecom.seed_uuid('account-horizon'), telecom.seed_uuid('subscriber-amelie'), 'Amelie phone', '7501', 'iPhone 17 Pro', true, true, NULL, current_date - 1000),
  (telecom.seed_uuid('line-luc'), telecom.seed_uuid('account-horizon'), telecom.seed_uuid('subscriber-luc'), 'Luc phone', '7502', 'Pixel 11', true, false, NULL, current_date - 800),
  (telecom.seed_uuid('line-ava'), telecom.seed_uuid('account-summit'), telecom.seed_uuid('subscriber-ava'), 'Ava work', '8601', 'iPhone 17 Pro', true, true, NULL, current_date - 750),
  (telecom.seed_uuid('line-ben'), telecom.seed_uuid('account-summit'), telecom.seed_uuid('subscriber-ben'), 'Ben work', '8602', 'Galaxy S27', true, true, NULL, current_date - 500);

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
CROSS JOIN generate_series(current_date - 364, current_date, interval '1 day') d;

INSERT INTO telecom.invoices (
  invoice_id, account_id, invoice_number, period_start, period_end, due_date,
  subtotal_cents, taxes_cents, adjustments_cents, total_cents, balance_cents, status, created_at
)
SELECT telecom.seed_uuid('invoice-' || a.account_number || '-' || month_offset::text),
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
       CASE WHEN month_offset = 0 THEN s.base_monthly_cents + 1100 ELSE 0 END,
       CASE WHEN month_offset = 0 THEN 'open'::telecom.invoice_status ELSE 'paid'::telecom.invoice_status END,
       date_trunc('month', current_date - (month_offset || ' month')::interval)
FROM telecom.accounts a
JOIN telecom.subscriptions s ON s.account_id = a.account_id
CROSS JOIN generate_series(0, 23) month_offset;

INSERT INTO telecom.payments (
  payment_id, account_id, invoice_id, paid_at, amount_cents, method_label, status, confirmation_code
)
SELECT telecom.seed_uuid('payment-' || i.invoice_number), i.account_id, i.invoice_id,
       i.due_date::timestamptz - interval '3 days', i.total_cents,
       CASE WHEN abs(hashtext(i.account_id::text)) % 2 = 0 THEN 'Visa ending 8842' ELSE 'Bank account ending 3110' END,
       'settled', 'CONF-' || upper(substr(md5(i.invoice_number), 1, 12))
FROM telecom.invoices i
WHERE i.status = 'paid';

INSERT INTO telecom.billing_preferences (
  billing_preference_id, account_id, autopay_enabled, paperless_billing, monthly_spend_alert_cents, payment_method_label
)
SELECT telecom.seed_uuid('billing-preference-' || account_number), account_id,
       account_number NOT IN ('US-100004', 'GB-300001'), true,
       CASE WHEN account_kind = 'business' THEN 50000 ELSE 20000 END,
       CASE WHEN account_number IN ('US-100001', 'US-100003', 'CA-200001')
         THEN 'Visa ending 8842' ELSE 'Bank account ending 3110' END
FROM telecom.accounts;

INSERT INTO telecom.support_agents (support_agent_id, principal_id, region, queue_name)
VALUES
  (telecom.seed_uuid('support-agent-1'), telecom.seed_uuid('principal-agent-1'), 'North America', 'Consumer Care'),
  (telecom.seed_uuid('support-agent-2'), telecom.seed_uuid('principal-agent-2'), 'EMEA', 'Business Care');

INSERT INTO telecom.support_cases (
  case_id, account_id, opened_by_principal_id, assigned_agent_id, case_number,
  category, subject, description, status, priority, latest_update_summary,
  latest_customer_note, latest_customer_note_length, customer_note_count,
  created_at, updated_at, version
)
VALUES
  (telecom.seed_uuid('case-atlas-roaming'), telecom.seed_uuid('account-atlas'), telecom.seed_uuid('principal-alex'), telecom.seed_uuid('support-agent-1'), 'LUNA-10001',
   'roaming', 'Review roaming for family trip', 'Confirm international roaming and day-pass coverage for the Atlas family trip to Japan.', 'waiting_customer', 'normal', 'Support asked for the travel dates and which family lines will be used abroad.',
   'Travel is September 12 through September 21, and all four lines are going.', length('Travel is September 12 through September 21, and all four lines are going.'), 1, now() - interval '4 days', now() - interval '8 hours', 3),
  (telecom.seed_uuid('case-atlas-maya-coverage'), telecom.seed_uuid('account-atlas'), telecom.seed_uuid('principal-maya'), telecom.seed_uuid('support-agent-1'), 'LUNA-10002',
   'coverage', 'Weak signal near school', 'Maya reports intermittent mobile data and dropped calls around the north side of her school campus.', 'open', 'normal', 'Network care is reviewing recent tower performance near the reported location.',
   'The issue is worst between 3:00 and 4:30 PM on weekdays.', length('The issue is worst between 3:00 and 4:30 PM on weekdays.'), 1, now() - interval '3 days', now() - interval '5 hours', 2),
  (telecom.seed_uuid('case-atlas-billing-credit'), telecom.seed_uuid('account-atlas'), telecom.seed_uuid('principal-alex'), telecom.seed_uuid('support-agent-1'), 'LUNA-10003',
   'billing', 'Duplicate international day-pass charge', 'A day-pass charge appeared twice for the same line and travel date.', 'resolved', 'normal', 'A duplicate charge was confirmed and a credit was issued to the next invoice.',
   NULL, 0, 0, now() - interval '42 days', now() - interval '36 days', 4),
  (telecom.seed_uuid('case-atlas-noah-device'), telecom.seed_uuid('account-atlas'), telecom.seed_uuid('principal-noah'), telecom.seed_uuid('support-agent-1'), 'LUNA-10004',
   'device', 'Voicemail setup after phone replacement', 'Noah needs visual voicemail restored after moving service to a replacement phone.', 'resolved', 'low', 'Visual voicemail was reprovisioned and the customer confirmed it is working.',
   'Voicemail is working now. Thanks.', length('Voicemail is working now. Thanks.'), 1, now() - interval '16 days', now() - interval '14 days', 3),
  (telecom.seed_uuid('case-meridian-device'), telecom.seed_uuid('account-meridian'), telecom.seed_uuid('principal-priya'), telecom.seed_uuid('support-agent-1'), 'LUNA-20001',
   'device', 'Replacement device activation', 'Activate a replacement device and transfer the existing eSIM for Priya.', 'resolved', 'normal', 'The replacement device was activated and test calls completed successfully.',
   'Calls and data are both working on the replacement phone.', length('Calls and data are both working on the replacement phone.'), 1, now() - interval '20 days', now() - interval '18 days', 3),
  (telecom.seed_uuid('case-meridian-leena-data'), telecom.seed_uuid('account-meridian'), telecom.seed_uuid('principal-leena'), telecom.seed_uuid('support-agent-1'), 'LUNA-20002',
   'technical', 'Mobile data pauses after Wi-Fi', 'Mobile data sometimes remains disconnected after leaving a Wi-Fi network.', 'waiting_customer', 'normal', 'Support provided network-reset steps and is waiting for the customer to test them.',
   'I reset the network settings and will test it tomorrow.', length('I reset the network settings and will test it tomorrow.'), 1, now() - interval '5 days', now() - interval '1 day', 2),
  (telecom.seed_uuid('case-chen-esim'), telecom.seed_uuid('account-chen'), telecom.seed_uuid('principal-eli'), telecom.seed_uuid('support-agent-1'), 'LUNA-30001',
   'device', 'eSIM transfer is pending', 'The eSIM transfer to a new Pixel remains pending after the activation flow completed.', 'open', 'high', 'Device activation is checking the pending eSIM download and account provisioning.',
   'The old phone still has service, so please do not deactivate it yet.', length('The old phone still has service, so please do not deactivate it yet.'), 1, now() - interval '2 days', now() - interval '3 hours', 2),
  (telecom.seed_uuid('case-nguyen-autopay'), telecom.seed_uuid('account-nguyen'), telecom.seed_uuid('principal-sophia'), telecom.seed_uuid('support-agent-1'), 'LUNA-40001',
   'billing', 'Autopay discount question', 'Confirm when the autopay discount becomes visible after enrolling a bank account.', 'waiting_customer', 'low', 'Billing explained the next-cycle timing and requested confirmation of the enrollment date.',
   NULL, 0, 0, now() - interval '7 days', now() - interval '2 days', 2),
  (telecom.seed_uuid('case-horizon-roaming'), telecom.seed_uuid('account-horizon'), telecom.seed_uuid('principal-amelie'), telecom.seed_uuid('support-agent-1'), 'LUNA-50001',
   'roaming', 'Canada and US roaming clarification', 'Clarify whether the family plan includes data roaming while traveling in the United States.', 'closed', 'low', 'Plan inclusion was confirmed, documented, and accepted by the customer.',
   NULL, 0, 0, now() - interval '75 days', now() - interval '70 days', 3),
  (telecom.seed_uuid('case-horizon-luc-coverage'), telecom.seed_uuid('account-horizon'), telecom.seed_uuid('principal-luc'), telecom.seed_uuid('support-agent-1'), 'LUNA-50002',
   'coverage', 'Indoor coverage at office', 'Luc reports calls dropping inside the west conference room at his office.', 'open', 'normal', 'Coverage support requested two recent timestamps to correlate with network telemetry.',
   'The latest drops were Tuesday at 10:12 AM and 2:46 PM.', length('The latest drops were Tuesday at 10:12 AM and 2:46 PM.'), 1, now() - interval '6 days', now() - interval '10 hours', 2),
  (telecom.seed_uuid('case-summit-billing'), telecom.seed_uuid('account-summit'), telecom.seed_uuid('principal-ava'), telecom.seed_uuid('support-agent-2'), 'LUNA-60001',
   'billing', 'Business invoice question', 'Review an unexpected equipment installment shown on the latest business invoice.', 'open', 'high', 'Business Care is reconciling the equipment installment against the signed order.',
   'Please compare it with order PO-8841 from our procurement team.', length('Please compare it with order PO-8841 from our procurement team.'), 1, now() - interval '2 days', now() - interval '2 hours', 2),
  (telecom.seed_uuid('case-summit-ben-device'), telecom.seed_uuid('account-summit'), telecom.seed_uuid('principal-ben'), telecom.seed_uuid('support-agent-2'), 'LUNA-60002',
   'technical', 'Work phone cannot receive MMS', 'Ben can send text messages but cannot receive picture messages on the work phone.', 'resolved', 'normal', 'The messaging profile was refreshed and inbound MMS testing succeeded.',
   'The test picture arrived successfully.', length('The test picture arrived successfully.'), 1, now() - interval '11 days', now() - interval '9 days', 3);

INSERT INTO telecom.support_case_notes (
  note_id, account_id, case_id, author_principal_id, note_kind, note_body, note_length, created_at
)
VALUES
  (telecom.seed_uuid('note-atlas-roaming-agent'), telecom.seed_uuid('account-atlas'), telecom.seed_uuid('case-atlas-roaming'), telecom.seed_uuid('principal-agent-1'), 'agent', 'Please share the travel dates and which lines will be used abroad.', length('Please share the travel dates and which lines will be used abroad.'), now() - interval '1 day'),
  (telecom.seed_uuid('note-atlas-roaming-customer'), telecom.seed_uuid('account-atlas'), telecom.seed_uuid('case-atlas-roaming'), telecom.seed_uuid('principal-alex'), 'customer', 'Travel is September 12 through September 21, and all four lines are going.', length('Travel is September 12 through September 21, and all four lines are going.'), now() - interval '8 hours'),
  (telecom.seed_uuid('note-atlas-maya-agent'), telecom.seed_uuid('account-atlas'), telecom.seed_uuid('case-atlas-maya-coverage'), telecom.seed_uuid('principal-agent-1'), 'agent', 'We are reviewing tower performance near the school campus.', length('We are reviewing tower performance near the school campus.'), now() - interval '1 day'),
  (telecom.seed_uuid('note-atlas-maya-customer'), telecom.seed_uuid('account-atlas'), telecom.seed_uuid('case-atlas-maya-coverage'), telecom.seed_uuid('principal-maya'), 'customer', 'The issue is worst between 3:00 and 4:30 PM on weekdays.', length('The issue is worst between 3:00 and 4:30 PM on weekdays.'), now() - interval '5 hours'),
  (telecom.seed_uuid('note-atlas-noah-customer'), telecom.seed_uuid('account-atlas'), telecom.seed_uuid('case-atlas-noah-device'), telecom.seed_uuid('principal-noah'), 'customer', 'Voicemail is working now. Thanks.', length('Voicemail is working now. Thanks.'), now() - interval '14 days'),
  (telecom.seed_uuid('note-meridian-device-customer'), telecom.seed_uuid('account-meridian'), telecom.seed_uuid('case-meridian-device'), telecom.seed_uuid('principal-priya'), 'customer', 'Calls and data are both working on the replacement phone.', length('Calls and data are both working on the replacement phone.'), now() - interval '18 days'),
  (telecom.seed_uuid('note-meridian-data-customer'), telecom.seed_uuid('account-meridian'), telecom.seed_uuid('case-meridian-leena-data'), telecom.seed_uuid('principal-leena'), 'customer', 'I reset the network settings and will test it tomorrow.', length('I reset the network settings and will test it tomorrow.'), now() - interval '1 day'),
  (telecom.seed_uuid('note-chen-esim-agent'), telecom.seed_uuid('account-chen'), telecom.seed_uuid('case-chen-esim'), telecom.seed_uuid('principal-agent-1'), 'agent', 'We are checking the pending eSIM download and provisioning state.', length('We are checking the pending eSIM download and provisioning state.'), now() - interval '8 hours'),
  (telecom.seed_uuid('note-chen-esim-customer'), telecom.seed_uuid('account-chen'), telecom.seed_uuid('case-chen-esim'), telecom.seed_uuid('principal-eli'), 'customer', 'The old phone still has service, so please do not deactivate it yet.', length('The old phone still has service, so please do not deactivate it yet.'), now() - interval '3 hours'),
  (telecom.seed_uuid('note-horizon-luc-customer'), telecom.seed_uuid('account-horizon'), telecom.seed_uuid('case-horizon-luc-coverage'), telecom.seed_uuid('principal-luc'), 'customer', 'The latest drops were Tuesday at 10:12 AM and 2:46 PM.', length('The latest drops were Tuesday at 10:12 AM and 2:46 PM.'), now() - interval '10 hours'),
  (telecom.seed_uuid('note-summit-billing-customer'), telecom.seed_uuid('account-summit'), telecom.seed_uuid('case-summit-billing'), telecom.seed_uuid('principal-ava'), 'customer', 'Please compare it with order PO-8841 from our procurement team.', length('Please compare it with order PO-8841 from our procurement team.'), now() - interval '2 hours'),
  (telecom.seed_uuid('note-summit-ben-customer'), telecom.seed_uuid('account-summit'), telecom.seed_uuid('case-summit-ben-device'), telecom.seed_uuid('principal-ben'), 'customer', 'The test picture arrived successfully.', length('The test picture arrived successfully.'), now() - interval '9 days');

DROP FUNCTION telecom.seed_uuid(text);
RESET ROLE;
