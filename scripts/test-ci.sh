#!/bin/bash
# CI test script that excludes PostgreSQL tests when DATABASE_URL is not set

set -e

if [ -z "$DATABASE_URL" ]; then
  echo "Skipping PostgreSQL tests (DATABASE_URL not set)"
  # Run all tests except PostgreSQL-specific ones
  crystal spec \
    --error-trace \
    $(find spec -name "*_spec.cr" | grep -v postgres_backend | sort) \
    -- --chaos
else
  echo "Running all tests including PostgreSQL"
  crystal spec --error-trace -- --chaos
fi