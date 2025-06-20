#!/bin/bash
# Script to test PostgreSQL backend with Docker

set -e

echo "Starting PostgreSQL test environment with Docker..."

# Start PostgreSQL container
docker-compose up -d postgres-test

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
for i in {1..30}; do
  if docker-compose exec -T postgres-test pg_isready -U mosquito >/dev/null 2>&1; then
    echo "PostgreSQL is ready!"
    break
  fi
  echo -n "."
  sleep 1
done

# Set environment variable for tests
export DATABASE_URL="postgres://mosquito:mosquito@localhost:5433/mosquito_test"

# Run the PostgreSQL backend tests
echo "Running PostgreSQL backend tests..."
crystal spec spec/mosquito/postgres_backend_spec.cr --no-color

# Cleanup
echo "Cleaning up..."
docker-compose down