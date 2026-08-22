\set ON_ERROR_STOP on
SET ROLE telecom_owner;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA telecom AUTHORIZATION telecom_owner;

CREATE TYPE telecom.account_kind AS ENUM ('individual', 'family', 'business');
CREATE TYPE telecom.membership_role AS ENUM ('owner', 'manager', 'member', 'support_agent');
CREATE TYPE telecom.record_status AS ENUM ('active', 'suspended', 'closed');
CREATE TYPE telecom.line_status AS ENUM ('active', 'suspended', 'canceled');
CREATE TYPE telecom.invoice_status AS ENUM ('draft', 'open', 'paid', 'past_due');
CREATE TYPE telecom.payment_status AS ENUM ('pending', 'settled', 'failed', 'refunded');
CREATE TYPE telecom.plan_code AS ENUM ('starter', 'unlimited', 'unlimited_plus', 'family_premium');
CREATE TYPE telecom.degree_of_access AS ENUM ('self', 'household');

CREATE TABLE telecom.accounts (
  account_id uuid PRIMARY KEY,
  account_number text NOT NULL UNIQUE,
  account_name text NOT NULL,
  account_kind telecom.account_kind NOT NULL,
  status telecom.record_status NOT NULL DEFAULT 'active',
  billing_cycle_day smallint NOT NULL CHECK (billing_cycle_day BETWEEN 1 AND 28),
  country_code char(2) NOT NULL,
  currency_code char(3) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1
);

CREATE TABLE telecom.principals (
  principal_id uuid PRIMARY KEY,
  email text NOT NULL UNIQUE,
  display_name text NOT NULL,
  password_hash text NOT NULL,
  locale text NOT NULL DEFAULT 'en-US',
  status telecom.record_status NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE telecom.subscribers (
  subscriber_id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES telecom.accounts(account_id),
  principal_id uuid UNIQUE REFERENCES telecom.principals(principal_id),
  display_name text NOT NULL,
  relationship_label text NOT NULL,
  access_level telecom.degree_of_access NOT NULL DEFAULT 'self',
  status telecom.record_status NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (account_id, subscriber_id)
);

CREATE TABLE telecom.account_memberships (
  membership_id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES telecom.accounts(account_id),
  principal_id uuid NOT NULL REFERENCES telecom.principals(principal_id),
  subscriber_id uuid NOT NULL REFERENCES telecom.subscribers(subscriber_id),
  membership_role telecom.membership_role NOT NULL,
  status telecom.record_status NOT NULL DEFAULT 'active',
  joined_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (account_id, principal_id),
  UNIQUE (account_id, membership_id),
  FOREIGN KEY (account_id, subscriber_id) REFERENCES telecom.subscribers(account_id, subscriber_id)
);

CREATE TABLE telecom.subscriptions (
  subscription_id uuid PRIMARY KEY,
  account_id uuid NOT NULL UNIQUE REFERENCES telecom.accounts(account_id),
  plan_code telecom.plan_code NOT NULL,
  plan_display_name text NOT NULL,
  base_monthly_cents integer NOT NULL CHECK (base_monthly_cents >= 0),
  included_lines smallint NOT NULL CHECK (included_lines >= 1),
  data_policy text NOT NULL,
  international_day_pass boolean NOT NULL DEFAULT false,
  effective_from date NOT NULL,
  contract_end_date date,
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1,
  UNIQUE (account_id, subscription_id)
);

CREATE TABLE telecom.service_lines (
  line_id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES telecom.accounts(account_id),
  subscriber_id uuid NOT NULL,
  line_label text NOT NULL,
  phone_last4 char(4) NOT NULL,
  status telecom.line_status NOT NULL DEFAULT 'active',
  device_name text NOT NULL,
  esim boolean NOT NULL DEFAULT true,
  international_roaming_enabled boolean NOT NULL DEFAULT false,
  data_limit_gb numeric(8,2),
  activated_on date NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1,
  UNIQUE (account_id, line_id),
  FOREIGN KEY (account_id, subscriber_id) REFERENCES telecom.subscribers(account_id, subscriber_id)
);

CREATE TABLE telecom.usage_daily (
  usage_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES telecom.accounts(account_id),
  line_id uuid NOT NULL,
  usage_date date NOT NULL,
  data_mb integer NOT NULL CHECK (data_mb >= 0),
  voice_minutes integer NOT NULL CHECK (voice_minutes >= 0),
  sms_count integer NOT NULL CHECK (sms_count >= 0),
  roaming_data_mb integer NOT NULL DEFAULT 0 CHECK (roaming_data_mb >= 0),
  UNIQUE (account_id, line_id, usage_date),
  FOREIGN KEY (account_id, line_id) REFERENCES telecom.service_lines(account_id, line_id)
);

CREATE TABLE telecom.invoices (
  invoice_id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES telecom.accounts(account_id),
  invoice_number text NOT NULL UNIQUE,
  period_start date NOT NULL,
  period_end date NOT NULL,
  due_date date NOT NULL,
  subtotal_cents integer NOT NULL CHECK (subtotal_cents >= 0),
  taxes_cents integer NOT NULL CHECK (taxes_cents >= 0),
  adjustments_cents integer NOT NULL DEFAULT 0,
  total_cents integer NOT NULL CHECK (total_cents >= 0),
  balance_cents integer NOT NULL CHECK (balance_cents >= 0),
  status telecom.invoice_status NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (account_id, invoice_id)
);

CREATE TABLE telecom.payments (
  payment_id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES telecom.accounts(account_id),
  invoice_id uuid NOT NULL,
  paid_at timestamptz NOT NULL,
  amount_cents integer NOT NULL CHECK (amount_cents > 0),
  method_label text NOT NULL,
  status telecom.payment_status NOT NULL,
  confirmation_code text NOT NULL UNIQUE,
  UNIQUE (account_id, payment_id),
  FOREIGN KEY (account_id, invoice_id) REFERENCES telecom.invoices(account_id, invoice_id)
);

CREATE TABLE telecom.billing_preferences (
  billing_preference_id uuid PRIMARY KEY,
  account_id uuid NOT NULL UNIQUE REFERENCES telecom.accounts(account_id),
  autopay_enabled boolean NOT NULL DEFAULT false,
  paperless_billing boolean NOT NULL DEFAULT true,
  monthly_spend_alert_cents integer NOT NULL DEFAULT 20000 CHECK (monthly_spend_alert_cents BETWEEN 1000 AND 50000),
  payment_method_label text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1,
  UNIQUE (account_id, billing_preference_id)
);

CREATE TABLE telecom.support_agents (
  support_agent_id uuid PRIMARY KEY,
  principal_id uuid NOT NULL UNIQUE REFERENCES telecom.principals(principal_id),
  region text NOT NULL,
  queue_name text NOT NULL,
  active boolean NOT NULL DEFAULT true
);

CREATE TABLE telecom.support_cases (
  case_id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES telecom.accounts(account_id),
  opened_by_principal_id uuid NOT NULL REFERENCES telecom.principals(principal_id),
  assigned_agent_id uuid REFERENCES telecom.support_agents(support_agent_id),
  case_number text NOT NULL CONSTRAINT support_cases_case_number_key UNIQUE,
  category text NOT NULL CONSTRAINT support_cases_category_check CHECK (category IN ('billing', 'coverage', 'device', 'plan', 'roaming', 'technical', 'other')),
  subject text NOT NULL,
  description text NOT NULL CONSTRAINT support_cases_description_check CHECK (length(description) BETWEEN 1 AND 2000),
  status text NOT NULL CHECK (status IN ('open', 'waiting_customer', 'resolved', 'closed')),
  priority text NOT NULL CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
  latest_update_summary text NOT NULL CONSTRAINT support_cases_latest_update_check CHECK (length(latest_update_summary) BETWEEN 1 AND 1000),
  latest_customer_note text CONSTRAINT support_cases_latest_note_check CHECK (latest_customer_note IS NULL OR length(latest_customer_note) BETWEEN 1 AND 1000),
  latest_customer_note_length integer NOT NULL DEFAULT 0,
  note_policy_units smallint NOT NULL DEFAULT 0 CHECK (note_policy_units IN (0, 1)),
  customer_note_count integer NOT NULL DEFAULT 0 CONSTRAINT support_cases_customer_note_count_check CHECK (customer_note_count >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1,
  CONSTRAINT support_cases_account_case_key UNIQUE (account_id, case_id),
  CONSTRAINT support_cases_latest_note_length_check CHECK (
    latest_customer_note_length BETWEEN 0 AND 1000
    AND latest_customer_note_length = COALESCE(length(latest_customer_note), 0)
  )
);

CREATE TABLE telecom.support_case_notes (
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

CREATE TABLE telecom.chat_sessions (
  chat_session_id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES telecom.accounts(account_id),
  principal_id uuid NOT NULL REFERENCES telecom.principals(principal_id),
  title text NOT NULL DEFAULT 'Customer service conversation',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (account_id, chat_session_id)
);

CREATE TABLE telecom.chat_messages (
  chat_message_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES telecom.accounts(account_id),
  chat_session_id uuid NOT NULL,
  principal_id uuid NOT NULL REFERENCES telecom.principals(principal_id),
  message_role text NOT NULL CHECK (message_role IN ('user', 'assistant')),
  content text NOT NULL CHECK (length(content) BETWEEN 1 AND 20000),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (account_id, chat_session_id) REFERENCES telecom.chat_sessions(account_id, chat_session_id)
);

CREATE TABLE telecom.plan_change_events (
  change_event_id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES telecom.accounts(account_id),
  principal_id uuid NOT NULL REFERENCES telecom.principals(principal_id),
  proposal_id text NOT NULL UNIQUE,
  action_name text NOT NULL,
  target_table text NOT NULL,
  target_id uuid NOT NULL,
  old_values jsonb NOT NULL,
  new_values jsonb NOT NULL,
  applied_at timestamptz NOT NULL DEFAULT now()
);

CREATE SCHEMA synapsor_app AUTHORIZATION telecom_owner;
CREATE TABLE synapsor_app.handler_receipts (
  idempotency_key text PRIMARY KEY,
  proposal_id text NOT NULL UNIQUE,
  account_id uuid NOT NULL,
  status text NOT NULL CHECK (status IN ('applied', 'already_applied', 'conflict', 'failed')),
  previous_version text,
  new_version text,
  response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX subscribers_account_idx ON telecom.subscribers(account_id);
CREATE INDEX memberships_account_principal_idx ON telecom.account_memberships(account_id, principal_id);
CREATE INDEX lines_account_subscriber_idx ON telecom.service_lines(account_id, subscriber_id);
CREATE INDEX usage_account_line_date_idx ON telecom.usage_daily(account_id, line_id, usage_date DESC);
CREATE INDEX invoices_account_period_idx ON telecom.invoices(account_id, period_end DESC);
CREATE INDEX payments_account_invoice_idx ON telecom.payments(account_id, invoice_id);
CREATE INDEX cases_account_updated_idx ON telecom.support_cases(account_id, updated_at DESC);
CREATE INDEX case_notes_account_case_created_idx ON telecom.support_case_notes(account_id, case_id, created_at DESC);
CREATE INDEX chat_sessions_principal_idx ON telecom.chat_sessions(account_id, principal_id, updated_at DESC);
CREATE INDEX chat_messages_session_idx ON telecom.chat_messages(account_id, chat_session_id, created_at);
CREATE INDEX change_events_account_time_idx ON telecom.plan_change_events(account_id, applied_at DESC);

RESET ROLE;
