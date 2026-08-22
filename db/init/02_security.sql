\set ON_ERROR_STOP on

SET ROLE telecom_owner;

GRANT USAGE, CREATE ON SCHEMA telecom TO telecom_policy;
GRANT SELECT ON telecom.accounts, telecom.principals, telecom.account_memberships,
  telecom.subscribers, telecom.service_lines, telecom.support_agents, telecom.support_cases
  TO telecom_policy;

CREATE OR REPLACE FUNCTION telecom.is_active_member(p_account_id uuid, p_principal_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, telecom
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM telecom.account_memberships m
    WHERE m.account_id = p_account_id
      AND m.principal_id = p_principal_id
      AND m.status = 'active'
  )
$$;

CREATE OR REPLACE FUNCTION telecom.can_manage_account(p_account_id uuid, p_principal_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, telecom
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM telecom.account_memberships m
    WHERE m.account_id = p_account_id
      AND m.principal_id = p_principal_id
      AND m.status = 'active'
      AND m.membership_role IN ('owner', 'manager')
  )
$$;

CREATE OR REPLACE FUNCTION telecom.can_view_subscriber(
  p_account_id uuid,
  p_subscriber_id uuid,
  p_principal_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, telecom
AS $$
  SELECT telecom.can_manage_account(p_account_id, p_principal_id)
      OR EXISTS (
        SELECT 1
        FROM telecom.subscribers s
        WHERE s.account_id = p_account_id
          AND s.subscriber_id = p_subscriber_id
          AND s.principal_id = p_principal_id
      )
$$;

CREATE OR REPLACE FUNCTION telecom.can_view_line(
  p_account_id uuid,
  p_line_id uuid,
  p_principal_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, telecom
AS $$
  SELECT telecom.can_manage_account(p_account_id, p_principal_id)
      OR EXISTS (
        SELECT 1
        FROM telecom.service_lines l
        JOIN telecom.subscribers s
          ON s.account_id = l.account_id
         AND s.subscriber_id = l.subscriber_id
        WHERE l.account_id = p_account_id
          AND l.line_id = p_line_id
          AND s.principal_id = p_principal_id
      )
$$;

CREATE OR REPLACE FUNCTION telecom.can_view_support_case(
  p_account_id uuid,
  p_case_id uuid,
  p_principal_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, telecom
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM telecom.support_cases c
    WHERE c.account_id = p_account_id
      AND c.case_id = p_case_id
      AND (
        c.opened_by_principal_id = p_principal_id
        OR telecom.can_manage_account(p_account_id, p_principal_id)
      )
  )
$$;

ALTER FUNCTION telecom.is_active_member(uuid, uuid) OWNER TO telecom_policy;
ALTER FUNCTION telecom.can_manage_account(uuid, uuid) OWNER TO telecom_policy;
ALTER FUNCTION telecom.can_view_subscriber(uuid, uuid, uuid) OWNER TO telecom_policy;
ALTER FUNCTION telecom.can_view_line(uuid, uuid, uuid) OWNER TO telecom_policy;
ALTER FUNCTION telecom.can_view_support_case(uuid, uuid, uuid) OWNER TO telecom_policy;
REVOKE ALL ON FUNCTION telecom.is_active_member(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION telecom.can_manage_account(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION telecom.can_view_subscriber(uuid, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION telecom.can_view_line(uuid, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION telecom.can_view_support_case(uuid, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION telecom.is_active_member(uuid, uuid) TO synapsor_reader, synapsor_writer, telecom_api;
GRANT EXECUTE ON FUNCTION telecom.can_manage_account(uuid, uuid) TO synapsor_reader, synapsor_writer, telecom_api;
GRANT EXECUTE ON FUNCTION telecom.can_view_subscriber(uuid, uuid, uuid) TO synapsor_reader, synapsor_writer, telecom_api;
GRANT EXECUTE ON FUNCTION telecom.can_view_line(uuid, uuid, uuid) TO synapsor_reader, synapsor_writer, telecom_api;
GRANT EXECUTE ON FUNCTION telecom.can_view_support_case(uuid, uuid, uuid) TO synapsor_reader, synapsor_writer, telecom_api;

CREATE OR REPLACE FUNCTION telecom.authenticate_principal(p_email text, p_password text)
RETURNS TABLE (
  principal_id uuid,
  display_name text,
  locale text,
  account_id uuid,
  account_number text,
  account_name text,
  membership_role telecom.membership_role
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, telecom, public
AS $$
  SELECT p.principal_id, p.display_name, p.locale,
         a.account_id, a.account_number, a.account_name, m.membership_role
  FROM telecom.principals p
  JOIN telecom.account_memberships m ON m.principal_id = p.principal_id
  JOIN telecom.accounts a ON a.account_id = m.account_id
  WHERE lower(p.email) = lower(p_email)
    AND p.password_hash = public.crypt(p_password, p.password_hash)
    AND p.status = 'active'
    AND m.status = 'active'
    AND a.status = 'active'
  ORDER BY a.account_number
$$;
ALTER FUNCTION telecom.authenticate_principal(text, text) OWNER TO telecom_policy;
REVOKE CREATE ON SCHEMA telecom FROM telecom_policy;
REVOKE ALL ON FUNCTION telecom.authenticate_principal(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION telecom.authenticate_principal(text, text) TO telecom_api;

DO $$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'accounts', 'subscribers', 'account_memberships', 'subscriptions',
    'service_lines', 'usage_daily', 'invoices', 'payments',
    'billing_preferences', 'support_cases', 'support_case_notes', 'chat_sessions', 'chat_messages'
  ] LOOP
    EXECUTE format('ALTER TABLE telecom.%I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format('ALTER TABLE telecom.%I FORCE ROW LEVEL SECURITY', table_name);
  END LOOP;
END
$$;

CREATE POLICY accounts_select ON telecom.accounts FOR SELECT
USING (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND telecom.is_active_member(account_id, nullif(current_setting('synapsor.principal', true), '')::uuid)
);

CREATE POLICY subscribers_select ON telecom.subscribers FOR SELECT
USING (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND telecom.can_view_subscriber(account_id, subscriber_id, nullif(current_setting('synapsor.principal', true), '')::uuid)
);

CREATE POLICY memberships_select ON telecom.account_memberships FOR SELECT
USING (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND (
    principal_id = nullif(current_setting('synapsor.principal', true), '')::uuid
    OR telecom.can_manage_account(account_id, nullif(current_setting('synapsor.principal', true), '')::uuid)
  )
);

CREATE POLICY subscriptions_select ON telecom.subscriptions FOR SELECT
USING (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND telecom.is_active_member(account_id, nullif(current_setting('synapsor.principal', true), '')::uuid)
);
CREATE POLICY subscriptions_update ON telecom.subscriptions FOR UPDATE TO synapsor_writer
USING (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND telecom.can_manage_account(account_id, nullif(current_setting('synapsor.principal', true), '')::uuid)
)
WITH CHECK (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND telecom.can_manage_account(account_id, nullif(current_setting('synapsor.principal', true), '')::uuid)
);

CREATE POLICY lines_select ON telecom.service_lines FOR SELECT
USING (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND telecom.can_view_line(account_id, line_id, nullif(current_setting('synapsor.principal', true), '')::uuid)
);
CREATE POLICY lines_update ON telecom.service_lines FOR UPDATE TO synapsor_writer
USING (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND telecom.can_view_line(account_id, line_id, nullif(current_setting('synapsor.principal', true), '')::uuid)
)
WITH CHECK (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND telecom.can_view_line(account_id, line_id, nullif(current_setting('synapsor.principal', true), '')::uuid)
);

CREATE POLICY usage_select ON telecom.usage_daily FOR SELECT
USING (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND telecom.can_view_line(account_id, line_id, nullif(current_setting('synapsor.principal', true), '')::uuid)
);

CREATE POLICY invoices_select ON telecom.invoices FOR SELECT
USING (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND telecom.can_manage_account(account_id, nullif(current_setting('synapsor.principal', true), '')::uuid)
);
CREATE POLICY payments_select ON telecom.payments FOR SELECT
USING (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND telecom.can_manage_account(account_id, nullif(current_setting('synapsor.principal', true), '')::uuid)
);

CREATE POLICY billing_preferences_select ON telecom.billing_preferences FOR SELECT
USING (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND telecom.can_manage_account(account_id, nullif(current_setting('synapsor.principal', true), '')::uuid)
);
CREATE POLICY billing_preferences_update ON telecom.billing_preferences FOR UPDATE TO synapsor_writer
USING (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND telecom.can_manage_account(account_id, nullif(current_setting('synapsor.principal', true), '')::uuid)
)
WITH CHECK (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND telecom.can_manage_account(account_id, nullif(current_setting('synapsor.principal', true), '')::uuid)
);

CREATE POLICY support_cases_select ON telecom.support_cases FOR SELECT
USING (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND (
    opened_by_principal_id = nullif(current_setting('synapsor.principal', true), '')::uuid
    OR telecom.can_manage_account(account_id, nullif(current_setting('synapsor.principal', true), '')::uuid)
  )
);
CREATE POLICY support_cases_update ON telecom.support_cases FOR UPDATE TO synapsor_writer
USING (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND telecom.can_view_support_case(account_id, case_id, nullif(current_setting('synapsor.principal', true), '')::uuid)
)
WITH CHECK (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND telecom.can_view_support_case(account_id, case_id, nullif(current_setting('synapsor.principal', true), '')::uuid)
);

CREATE POLICY support_case_notes_select ON telecom.support_case_notes FOR SELECT
USING (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND telecom.can_view_support_case(account_id, case_id, nullif(current_setting('synapsor.principal', true), '')::uuid)
);
CREATE POLICY support_case_notes_insert ON telecom.support_case_notes FOR INSERT TO synapsor_writer
WITH CHECK (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND author_principal_id = nullif(current_setting('synapsor.principal', true), '')::uuid
  AND note_kind = 'customer'
  AND telecom.can_view_support_case(account_id, case_id, nullif(current_setting('synapsor.principal', true), '')::uuid)
);

CREATE POLICY chat_sessions_all ON telecom.chat_sessions FOR ALL TO telecom_api
USING (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND principal_id = nullif(current_setting('synapsor.principal', true), '')::uuid
)
WITH CHECK (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND principal_id = nullif(current_setting('synapsor.principal', true), '')::uuid
);
CREATE POLICY chat_messages_all ON telecom.chat_messages FOR ALL TO telecom_api
USING (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND principal_id = nullif(current_setting('synapsor.principal', true), '')::uuid
)
WITH CHECK (
  account_id = nullif(current_setting('synapsor.tenant_id', true), '')::uuid
  AND principal_id = nullif(current_setting('synapsor.principal', true), '')::uuid
);

GRANT USAGE ON SCHEMA telecom TO synapsor_reader, synapsor_writer, telecom_api;
GRANT USAGE ON SCHEMA synapsor_app TO synapsor_writer;
GRANT SELECT ON telecom.accounts, telecom.account_memberships, telecom.subscribers,
  telecom.subscriptions, telecom.service_lines, telecom.usage_daily,
  telecom.invoices, telecom.payments, telecom.billing_preferences,
  telecom.support_cases, telecom.support_case_notes
  TO synapsor_reader;
GRANT SELECT ON telecom.subscriptions, telecom.service_lines, telecom.billing_preferences,
  telecom.support_cases, telecom.support_case_notes TO synapsor_writer;
GRANT UPDATE (plan_code, plan_display_name, base_monthly_cents, included_lines,
  data_policy, international_day_pass, effective_from, updated_at, version)
  ON telecom.subscriptions TO synapsor_writer;
GRANT UPDATE (international_roaming_enabled, updated_at, version)
  ON telecom.service_lines TO synapsor_writer;
GRANT UPDATE (autopay_enabled, paperless_billing, monthly_spend_alert_cents, payment_method_label, updated_at, version)
  ON telecom.billing_preferences TO synapsor_writer;
GRANT UPDATE (latest_customer_note, latest_customer_note_length, note_policy_units, customer_note_count, updated_at, version)
  ON telecom.support_cases TO synapsor_writer;
GRANT INSERT ON telecom.support_case_notes TO synapsor_writer;
GRANT INSERT ON telecom.plan_change_events TO synapsor_writer;
GRANT SELECT, INSERT ON synapsor_app.handler_receipts TO synapsor_writer;
GRANT SELECT, INSERT, UPDATE ON telecom.chat_sessions, telecom.chat_messages TO telecom_api;
GRANT USAGE, SELECT ON SEQUENCE telecom.chat_messages_chat_message_id_seq TO telecom_api;

RESET ROLE;
