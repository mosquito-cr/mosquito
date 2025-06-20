#!/bin/bash
# Run core Mosquito tests (excluding backend-specific features)

set -e

echo "Running core Mosquito tests..."

# Core backend interface tests
echo "Running backend interface tests..."
crystal spec \
  spec/mosquito/backend/hash_storage_spec.cr \
  spec/mosquito/backend/lock_spec.cr \
  spec/mosquito/backend/queueing_spec.cr \
  spec/mosquito/backend/overseer_spec.cr \
  spec/mosquito/backend/deleting_spec.cr

# Core functionality tests
echo "Running core functionality tests..."
crystal spec \
  spec/mosquito/base_spec.cr \
  spec/mosquito/job_run_spec.cr \
  spec/mosquito/queue_spec.cr \
  spec/mosquito/key_builder_spec.cr \
  spec/mosquito/runnable_spec.cr \
  spec/mosquito/periodic_job_spec.cr \
  spec/mosquito/periodic_job_run_spec.cr

# Job run tests
echo "Running job run tests..."
crystal spec spec/mosquito/job_run/*.cr

# Serializer tests
echo "Running serializer tests..."
crystal spec spec/mosquito/serializers/*.cr

echo "Core tests completed!"