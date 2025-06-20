#!/bin/bash
# Setup script for PostgreSQL test database

DB_NAME="mosquito_test"
DB_USER="${PGUSER:-$USER}"

echo "Setting up PostgreSQL test database..."

# Create database if it doesn't exist
createdb "$DB_NAME" 2>/dev/null || echo "Database $DB_NAME already exists"

# Apply schema
psql -d "$DB_NAME" -f src/mosquito/postgres_backend/schema.sql

echo "PostgreSQL test database setup complete!"
echo "You can now run the tests with: crystal spec spec/mosquito/postgres_backend_spec.cr"