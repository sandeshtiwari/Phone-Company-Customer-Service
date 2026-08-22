\set ON_ERROR_STOP on

-- Idempotent helpdesk expansion for both existing Docker volumes and fresh
-- databases. Docker initialization creates the base objects; this migration
-- enriches them and safely seeds reviewed support-case scenarios.

SET ROLE telecom_owner;

ALTER TABLE telecom.support_cases ADD COLUMN IF NOT EXISTS case_number text;
ALTER TABLE telecom.support_cases ADD COLUMN IF NOT EXISTS category text;
ALTER TABLE telecom.support_cases ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE telecom.support_cases ADD COLUMN IF NOT EXISTS latest_update_summary text;
ALTER TABLE telecom.support_cases ADD COLUMN IF NOT EXISTS latest_customer_note text;
ALTER TABLE telecom.support_cases ADD COLUMN IF NOT EXISTS latest_customer_note_length integer NOT NULL DEFAULT 0;
ALTER TABLE telecom.support_cases ADD COLUMN IF NOT EXISTS note_policy_units smallint NOT NULL DEFAULT 0;
ALTER TABLE telecom.support_cases ADD COLUMN IF NOT EXISTS customer_note_count integer NOT NULL DEFAULT 0;
ALTER TABLE telecom.support_cases ADD COLUMN IF NOT EXISTS version bigint NOT NULL DEFAULT 1;

RESET ROLE;

CREATE OR REPLACE FUNCTION pg_temp.seed_uuid(seed text)
RETURNS uuid LANGUAGE sql IMMUTABLE STRICT AS $$
  SELECT (
    substr(md5(seed), 1, 8) || '-' || substr(md5(seed), 9, 4) || '-' ||
    substr(md5(seed), 13, 4) || '-' || substr(md5(seed), 17, 4) || '-' ||
    substr(md5(seed), 21, 12)
  )::uuid
$$;

INSERT INTO telecom.support_cases (
  case_id, account_id, opened_by_principal_id, assigned_agent_id, case_number,
  category, subject, description, status, priority, latest_update_summary,
  latest_customer_note, latest_customer_note_length, customer_note_count,
  created_at, updated_at, version
)
VALUES
  (pg_temp.seed_uuid('case-atlas-roaming'), pg_temp.seed_uuid('account-atlas'), pg_temp.seed_uuid('principal-alex'), pg_temp.seed_uuid('support-agent-1'), 'LUNA-10001',
   'roaming', 'Review roaming for family trip', 'Confirm international roaming and day-pass coverage for the Atlas family trip to Japan.', 'waiting_customer', 'normal', 'Support asked for the travel dates and which family lines will be used abroad.',
   'Travel is September 12 through September 21, and all four lines are going.', length('Travel is September 12 through September 21, and all four lines are going.'), 1, now() - interval '4 days', now() - interval '8 hours', 3),
  (pg_temp.seed_uuid('case-atlas-maya-coverage'), pg_temp.seed_uuid('account-atlas'), pg_temp.seed_uuid('principal-maya'), pg_temp.seed_uuid('support-agent-1'), 'LUNA-10002',
   'coverage', 'Weak signal near school', 'Maya reports intermittent mobile data and dropped calls around the north side of her school campus.', 'open', 'normal', 'Network care is reviewing recent tower performance near the reported location.',
   'The issue is worst between 3:00 and 4:30 PM on weekdays.', length('The issue is worst between 3:00 and 4:30 PM on weekdays.'), 1, now() - interval '3 days', now() - interval '5 hours', 2),
  (pg_temp.seed_uuid('case-atlas-billing-credit'), pg_temp.seed_uuid('account-atlas'), pg_temp.seed_uuid('principal-alex'), pg_temp.seed_uuid('support-agent-1'), 'LUNA-10003',
   'billing', 'Duplicate international day-pass charge', 'A day-pass charge appeared twice for the same line and travel date.', 'resolved', 'normal', 'A duplicate charge was confirmed and a credit was issued to the next invoice.',
   NULL, 0, 0, now() - interval '42 days', now() - interval '36 days', 4),
  (pg_temp.seed_uuid('case-atlas-noah-device'), pg_temp.seed_uuid('account-atlas'), pg_temp.seed_uuid('principal-noah'), pg_temp.seed_uuid('support-agent-1'), 'LUNA-10004',
   'device', 'Voicemail setup after phone replacement', 'Noah needs visual voicemail restored after moving service to a replacement phone.', 'resolved', 'low', 'Visual voicemail was reprovisioned and the customer confirmed it is working.',
   'Voicemail is working now. Thanks.', length('Voicemail is working now. Thanks.'), 1, now() - interval '16 days', now() - interval '14 days', 3),
  (pg_temp.seed_uuid('case-meridian-device'), pg_temp.seed_uuid('account-meridian'), pg_temp.seed_uuid('principal-priya'), pg_temp.seed_uuid('support-agent-1'), 'LUNA-20001',
   'device', 'Replacement device activation', 'Activate a replacement device and transfer the existing eSIM for Priya.', 'resolved', 'normal', 'The replacement device was activated and test calls completed successfully.',
   'Calls and data are both working on the replacement phone.', length('Calls and data are both working on the replacement phone.'), 1, now() - interval '20 days', now() - interval '18 days', 3),
  (pg_temp.seed_uuid('case-meridian-leena-data'), pg_temp.seed_uuid('account-meridian'), pg_temp.seed_uuid('principal-leena'), pg_temp.seed_uuid('support-agent-1'), 'LUNA-20002',
   'technical', 'Mobile data pauses after Wi-Fi', 'Mobile data sometimes remains disconnected after leaving a Wi-Fi network.', 'waiting_customer', 'normal', 'Support provided network-reset steps and is waiting for the customer to test them.',
   'I reset the network settings and will test it tomorrow.', length('I reset the network settings and will test it tomorrow.'), 1, now() - interval '5 days', now() - interval '1 day', 2),
  (pg_temp.seed_uuid('case-chen-esim'), pg_temp.seed_uuid('account-chen'), pg_temp.seed_uuid('principal-eli'), pg_temp.seed_uuid('support-agent-1'), 'LUNA-30001',
   'device', 'eSIM transfer is pending', 'The eSIM transfer to a new Pixel remains pending after the activation flow completed.', 'open', 'high', 'Device activation is checking the pending eSIM download and account provisioning.',
   'The old phone still has service, so please do not deactivate it yet.', length('The old phone still has service, so please do not deactivate it yet.'), 1, now() - interval '2 days', now() - interval '3 hours', 2),
  (pg_temp.seed_uuid('case-nguyen-autopay'), pg_temp.seed_uuid('account-nguyen'), pg_temp.seed_uuid('principal-sophia'), pg_temp.seed_uuid('support-agent-1'), 'LUNA-40001',
   'billing', 'Autopay discount question', 'Confirm when the autopay discount becomes visible after enrolling a bank account.', 'waiting_customer', 'low', 'Billing explained the next-cycle timing and requested confirmation of the enrollment date.',
   NULL, 0, 0, now() - interval '7 days', now() - interval '2 days', 2),
  (pg_temp.seed_uuid('case-horizon-roaming'), pg_temp.seed_uuid('account-horizon'), pg_temp.seed_uuid('principal-amelie'), pg_temp.seed_uuid('support-agent-1'), 'LUNA-50001',
   'roaming', 'Canada and US roaming clarification', 'Clarify whether the family plan includes data roaming while traveling in the United States.', 'closed', 'low', 'Plan inclusion was confirmed, documented, and accepted by the customer.',
   NULL, 0, 0, now() - interval '75 days', now() - interval '70 days', 3),
  (pg_temp.seed_uuid('case-horizon-luc-coverage'), pg_temp.seed_uuid('account-horizon'), pg_temp.seed_uuid('principal-luc'), pg_temp.seed_uuid('support-agent-1'), 'LUNA-50002',
   'coverage', 'Indoor coverage at office', 'Luc reports calls dropping inside the west conference room at his office.', 'open', 'normal', 'Coverage support requested two recent timestamps to correlate with network telemetry.',
   'The latest drops were Tuesday at 10:12 AM and 2:46 PM.', length('The latest drops were Tuesday at 10:12 AM and 2:46 PM.'), 1, now() - interval '6 days', now() - interval '10 hours', 2),
  (pg_temp.seed_uuid('case-summit-billing'), pg_temp.seed_uuid('account-summit'), pg_temp.seed_uuid('principal-ava'), pg_temp.seed_uuid('support-agent-2'), 'LUNA-60001',
   'billing', 'Business invoice question', 'Review an unexpected equipment installment shown on the latest business invoice.', 'open', 'high', 'Business Care is reconciling the equipment installment against the signed order.',
   'Please compare it with order PO-8841 from our procurement team.', length('Please compare it with order PO-8841 from our procurement team.'), 1, now() - interval '2 days', now() - interval '2 hours', 2),
  (pg_temp.seed_uuid('case-summit-ben-device'), pg_temp.seed_uuid('account-summit'), pg_temp.seed_uuid('principal-ben'), pg_temp.seed_uuid('support-agent-2'), 'LUNA-60002',
   'technical', 'Work phone cannot receive MMS', 'Ben can send text messages but cannot receive picture messages on the work phone.', 'resolved', 'normal', 'The messaging profile was refreshed and inbound MMS testing succeeded.',
   'The test picture arrived successfully.', length('The test picture arrived successfully.'), 1, now() - interval '11 days', now() - interval '9 days', 3)
ON CONFLICT (case_id) DO UPDATE SET
  case_number = EXCLUDED.case_number,
  category = EXCLUDED.category,
  description = EXCLUDED.description,
  latest_update_summary = EXCLUDED.latest_update_summary,
  latest_customer_note = COALESCE(telecom.support_cases.latest_customer_note, EXCLUDED.latest_customer_note),
  latest_customer_note_length = CASE
    WHEN telecom.support_cases.latest_customer_note IS NULL THEN EXCLUDED.latest_customer_note_length
    ELSE telecom.support_cases.latest_customer_note_length
  END,
  customer_note_count = GREATEST(telecom.support_cases.customer_note_count, EXCLUDED.customer_note_count),
  version = GREATEST(telecom.support_cases.version, EXCLUDED.version);

SET ROLE telecom_owner;

ALTER TABLE telecom.support_cases ALTER COLUMN case_number SET NOT NULL;
ALTER TABLE telecom.support_cases ALTER COLUMN category SET NOT NULL;
ALTER TABLE telecom.support_cases ALTER COLUMN description SET NOT NULL;
ALTER TABLE telecom.support_cases ALTER COLUMN latest_update_summary SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'support_cases_account_case_key') THEN
    ALTER TABLE telecom.support_cases ADD CONSTRAINT support_cases_account_case_key UNIQUE (account_id, case_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'support_cases_case_number_key') THEN
    ALTER TABLE telecom.support_cases ADD CONSTRAINT support_cases_case_number_key UNIQUE (case_number);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'support_cases_category_check') THEN
    ALTER TABLE telecom.support_cases ADD CONSTRAINT support_cases_category_check CHECK (category IN ('billing', 'coverage', 'device', 'plan', 'roaming', 'technical', 'other'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'support_cases_description_check') THEN
    ALTER TABLE telecom.support_cases ADD CONSTRAINT support_cases_description_check CHECK (length(description) BETWEEN 1 AND 2000);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'support_cases_latest_update_check') THEN
    ALTER TABLE telecom.support_cases ADD CONSTRAINT support_cases_latest_update_check CHECK (length(latest_update_summary) BETWEEN 1 AND 1000);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'support_cases_latest_note_check') THEN
    ALTER TABLE telecom.support_cases ADD CONSTRAINT support_cases_latest_note_check CHECK (latest_customer_note IS NULL OR length(latest_customer_note) BETWEEN 1 AND 1000);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'support_cases_latest_note_length_check') THEN
    ALTER TABLE telecom.support_cases ADD CONSTRAINT support_cases_latest_note_length_check CHECK (latest_customer_note_length BETWEEN 0 AND 1000 AND latest_customer_note_length = COALESCE(length(latest_customer_note), 0));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'support_cases_customer_note_count_check') THEN
    ALTER TABLE telecom.support_cases ADD CONSTRAINT support_cases_customer_note_count_check CHECK (customer_note_count >= 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'support_cases_note_policy_units_check') THEN
    ALTER TABLE telecom.support_cases ADD CONSTRAINT support_cases_note_policy_units_check CHECK (note_policy_units IN (0, 1));
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS telecom.support_case_notes (
  note_id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES telecom.accounts(account_id),
  case_id uuid NOT NULL,
  author_principal_id uuid NOT NULL REFERENCES telecom.principals(principal_id),
  note_kind text NOT NULL CHECK (note_kind IN ('customer', 'agent', 'system')),
  note_body text NOT NULL CHECK (length(note_body) BETWEEN 1 AND 1000),
  note_length integer NOT NULL CHECK (note_length = length(note_body)),
  proposal_id text UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (account_id, note_id),
  FOREIGN KEY (account_id, case_id) REFERENCES telecom.support_cases(account_id, case_id)
);

CREATE INDEX IF NOT EXISTS case_notes_account_case_created_idx
  ON telecom.support_case_notes(account_id, case_id, created_at DESC);

RESET ROLE;

INSERT INTO telecom.support_case_notes (
  note_id, account_id, case_id, author_principal_id, note_kind, note_body, note_length, created_at
)
VALUES
  (pg_temp.seed_uuid('note-atlas-roaming-agent'), pg_temp.seed_uuid('account-atlas'), pg_temp.seed_uuid('case-atlas-roaming'), pg_temp.seed_uuid('principal-agent-1'), 'agent', 'Please share the travel dates and which lines will be used abroad.', length('Please share the travel dates and which lines will be used abroad.'), now() - interval '1 day'),
  (pg_temp.seed_uuid('note-atlas-roaming-customer'), pg_temp.seed_uuid('account-atlas'), pg_temp.seed_uuid('case-atlas-roaming'), pg_temp.seed_uuid('principal-alex'), 'customer', 'Travel is September 12 through September 21, and all four lines are going.', length('Travel is September 12 through September 21, and all four lines are going.'), now() - interval '8 hours'),
  (pg_temp.seed_uuid('note-atlas-maya-agent'), pg_temp.seed_uuid('account-atlas'), pg_temp.seed_uuid('case-atlas-maya-coverage'), pg_temp.seed_uuid('principal-agent-1'), 'agent', 'We are reviewing tower performance near the school campus.', length('We are reviewing tower performance near the school campus.'), now() - interval '1 day'),
  (pg_temp.seed_uuid('note-atlas-maya-customer'), pg_temp.seed_uuid('account-atlas'), pg_temp.seed_uuid('case-atlas-maya-coverage'), pg_temp.seed_uuid('principal-maya'), 'customer', 'The issue is worst between 3:00 and 4:30 PM on weekdays.', length('The issue is worst between 3:00 and 4:30 PM on weekdays.'), now() - interval '5 hours'),
  (pg_temp.seed_uuid('note-atlas-noah-customer'), pg_temp.seed_uuid('account-atlas'), pg_temp.seed_uuid('case-atlas-noah-device'), pg_temp.seed_uuid('principal-noah'), 'customer', 'Voicemail is working now. Thanks.', length('Voicemail is working now. Thanks.'), now() - interval '14 days'),
  (pg_temp.seed_uuid('note-meridian-device-customer'), pg_temp.seed_uuid('account-meridian'), pg_temp.seed_uuid('case-meridian-device'), pg_temp.seed_uuid('principal-priya'), 'customer', 'Calls and data are both working on the replacement phone.', length('Calls and data are both working on the replacement phone.'), now() - interval '18 days'),
  (pg_temp.seed_uuid('note-meridian-data-customer'), pg_temp.seed_uuid('account-meridian'), pg_temp.seed_uuid('case-meridian-leena-data'), pg_temp.seed_uuid('principal-leena'), 'customer', 'I reset the network settings and will test it tomorrow.', length('I reset the network settings and will test it tomorrow.'), now() - interval '1 day'),
  (pg_temp.seed_uuid('note-chen-esim-agent'), pg_temp.seed_uuid('account-chen'), pg_temp.seed_uuid('case-chen-esim'), pg_temp.seed_uuid('principal-agent-1'), 'agent', 'We are checking the pending eSIM download and provisioning state.', length('We are checking the pending eSIM download and provisioning state.'), now() - interval '8 hours'),
  (pg_temp.seed_uuid('note-chen-esim-customer'), pg_temp.seed_uuid('account-chen'), pg_temp.seed_uuid('case-chen-esim'), pg_temp.seed_uuid('principal-eli'), 'customer', 'The old phone still has service, so please do not deactivate it yet.', length('The old phone still has service, so please do not deactivate it yet.'), now() - interval '3 hours'),
  (pg_temp.seed_uuid('note-horizon-luc-customer'), pg_temp.seed_uuid('account-horizon'), pg_temp.seed_uuid('case-horizon-luc-coverage'), pg_temp.seed_uuid('principal-luc'), 'customer', 'The latest drops were Tuesday at 10:12 AM and 2:46 PM.', length('The latest drops were Tuesday at 10:12 AM and 2:46 PM.'), now() - interval '10 hours'),
  (pg_temp.seed_uuid('note-summit-billing-customer'), pg_temp.seed_uuid('account-summit'), pg_temp.seed_uuid('case-summit-billing'), pg_temp.seed_uuid('principal-ava'), 'customer', 'Please compare it with order PO-8841 from our procurement team.', length('Please compare it with order PO-8841 from our procurement team.'), now() - interval '2 hours'),
  (pg_temp.seed_uuid('note-summit-ben-customer'), pg_temp.seed_uuid('account-summit'), pg_temp.seed_uuid('case-summit-ben-device'), pg_temp.seed_uuid('principal-ben'), 'customer', 'The test picture arrived successfully.', length('The test picture arrived successfully.'), now() - interval '9 days')
ON CONFLICT (note_id) DO NOTHING;

SET ROLE telecom_owner;

GRANT SELECT ON telecom.support_cases TO telecom_policy;

CREATE OR REPLACE FUNCTION telecom.can_view_support_case(
  p_account_id uuid, p_case_id uuid, p_principal_id uuid
)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, telecom AS $$
  SELECT EXISTS (
    SELECT 1 FROM telecom.support_cases c
    WHERE c.account_id = p_account_id AND c.case_id = p_case_id
      AND (c.opened_by_principal_id = p_principal_id
           OR telecom.can_manage_account(p_account_id, p_principal_id))
  )
$$;
RESET ROLE;
ALTER FUNCTION telecom.can_view_support_case(uuid, uuid, uuid) OWNER TO telecom_policy;
REVOKE ALL ON FUNCTION telecom.can_view_support_case(uuid, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION telecom.can_view_support_case(uuid, uuid, uuid)
  TO synapsor_reader, synapsor_writer, telecom_api;

SET ROLE telecom_owner;

ALTER TABLE telecom.support_case_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE telecom.support_case_notes FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS support_cases_update ON telecom.support_cases;
CREATE POLICY support_cases_update ON telecom.support_cases FOR UPDATE TO synapsor_writer
USING (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND telecom.can_view_support_case(account_id, case_id, nullif(current_setting('synapsor.principal', true), '')::uuid)
)
WITH CHECK (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND telecom.can_view_support_case(account_id, case_id, nullif(current_setting('synapsor.principal', true), '')::uuid)
);

DROP POLICY IF EXISTS support_case_notes_select ON telecom.support_case_notes;
CREATE POLICY support_case_notes_select ON telecom.support_case_notes FOR SELECT
USING (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND telecom.can_view_support_case(account_id, case_id, nullif(current_setting('synapsor.principal', true), '')::uuid)
);
DROP POLICY IF EXISTS support_case_notes_insert ON telecom.support_case_notes;
CREATE POLICY support_case_notes_insert ON telecom.support_case_notes FOR INSERT TO synapsor_writer
WITH CHECK (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND author_principal_id = nullif(current_setting('synapsor.principal', true), '')::uuid
  AND note_kind = 'customer'
  AND telecom.can_view_support_case(account_id, case_id, nullif(current_setting('synapsor.principal', true), '')::uuid)
);

GRANT SELECT ON telecom.support_cases, telecom.support_case_notes TO synapsor_reader, synapsor_writer;
GRANT UPDATE (latest_customer_note, latest_customer_note_length, note_policy_units, customer_note_count, updated_at, version)
  ON telecom.support_cases TO synapsor_writer;
GRANT INSERT ON telecom.support_case_notes TO synapsor_writer;

CREATE OR REPLACE FUNCTION telecom.sync_support_case_projection(p_account_id uuid, p_case_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, telecom, customer_explore AS $$
BEGIN
  IF p_account_id IS DISTINCT FROM nullif(current_setting('synapsor.tenant_id', true), '')::uuid
     OR NOT telecom.can_view_support_case(p_account_id, p_case_id, nullif(current_setting('synapsor.principal', true), '')::uuid) THEN
    RAISE EXCEPTION 'scope denied';
  END IF;

  INSERT INTO customer_explore.support_cases
    (explore_row_id, account_id, viewer_principal_id, case_id, subject, status,
     priority, created_at, updated_at)
  SELECT md5(m.principal_id::text || ':' || c.case_id::text)::uuid,
         c.account_id, m.principal_id, c.case_id, c.subject, c.status,
         c.priority, c.created_at, c.updated_at
  FROM telecom.support_cases c
  JOIN telecom.account_memberships m USING (account_id)
  WHERE c.account_id = p_account_id AND c.case_id = p_case_id
    AND m.status = 'active'
    AND (m.membership_role IN ('owner', 'manager') OR c.opened_by_principal_id = m.principal_id)
  ON CONFLICT (account_id, viewer_principal_id, case_id) DO UPDATE
  SET subject = EXCLUDED.subject, status = EXCLUDED.status,
      priority = EXCLUDED.priority, updated_at = EXCLUDED.updated_at;
END $$;
REVOKE ALL ON FUNCTION telecom.sync_support_case_projection(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION telecom.sync_support_case_projection(uuid, uuid) TO synapsor_writer;

RESET ROLE;

INSERT INTO customer_explore.support_cases
  (explore_row_id, account_id, viewer_principal_id, case_id, subject, status,
   priority, created_at, updated_at)
SELECT md5(m.principal_id::text || ':' || c.case_id::text)::uuid,
       c.account_id, m.principal_id, c.case_id, c.subject, c.status,
       c.priority, c.created_at, c.updated_at
FROM telecom.support_cases c
JOIN telecom.account_memberships m USING (account_id)
WHERE m.status = 'active'
  AND (m.membership_role IN ('owner', 'manager') OR c.opened_by_principal_id = m.principal_id)
ON CONFLICT (account_id, viewer_principal_id, case_id) DO UPDATE
SET subject = EXCLUDED.subject, status = EXCLUDED.status,
    priority = EXCLUDED.priority, updated_at = EXCLUDED.updated_at;
