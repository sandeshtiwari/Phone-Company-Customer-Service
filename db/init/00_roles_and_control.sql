\set ON_ERROR_STOP on

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'telecom_owner') THEN
    CREATE ROLE telecom_owner NOLOGIN NOSUPERUSER NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'telecom_policy') THEN
    CREATE ROLE telecom_policy NOLOGIN NOSUPERUSER BYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'synapsor_reader') THEN
    CREATE ROLE synapsor_reader LOGIN PASSWORD 'synapsor_reader_pw' NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'synapsor_explore_reader') THEN
    CREATE ROLE synapsor_explore_reader LOGIN PASSWORD 'synapsor_explore_reader_pw' NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'synapsor_writer') THEN
    CREATE ROLE synapsor_writer LOGIN PASSWORD 'synapsor_writer_pw' NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'telecom_api') THEN
    CREATE ROLE telecom_api LOGIN PASSWORD 'telecom_api_pw' NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'synapsor_control') THEN
    CREATE ROLE synapsor_control LOGIN PASSWORD 'synapsor_control_pw' NOSUPERUSER CREATEDB NOCREATEROLE NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'telecom_handler_ledger') THEN
    CREATE ROLE telecom_handler_ledger LOGIN PASSWORD 'telecom_handler_ledger_pw' NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
  END IF;
END
$$;

GRANT telecom_policy TO telecom_owner;

SELECT 'CREATE DATABASE synapsor_control OWNER synapsor_control'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'synapsor_control')\gexec

ALTER DATABASE telecom_customer_service OWNER TO telecom_owner;
REVOKE ALL ON DATABASE telecom_customer_service FROM PUBLIC;
GRANT CONNECT ON DATABASE telecom_customer_service TO synapsor_reader, synapsor_explore_reader, synapsor_writer, telecom_api;
REVOKE ALL ON DATABASE synapsor_control FROM PUBLIC;
GRANT CONNECT ON DATABASE synapsor_control TO synapsor_control;
GRANT CONNECT ON DATABASE synapsor_control TO telecom_handler_ledger;
