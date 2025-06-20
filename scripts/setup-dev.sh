#!/bin/bash
# Development environment setup script

set -e

echo "Setting up Mosquito development environment..."

# Check for Docker
if ! command -v docker &> /dev/null; then
    echo "Docker is required but not installed. Please install Docker."
    exit 1
fi

# Check for Crystal
if ! command -v crystal &> /dev/null; then
    echo "Crystal is required but not installed. Please install Crystal."
    exit 1
fi

# Start all services
echo "Starting PostgreSQL and Redis with Docker..."
docker-compose up -d

# Wait for services to be ready
echo "Waiting for services to be ready..."
for service in postgres redis; do
    echo -n "Waiting for $service..."
    for i in {1..30}; do
        if docker-compose exec -T $service sh -c 'exit 0' >/dev/null 2>&1; then
            echo " ready!"
            break
        fi
        echo -n "."
        sleep 1
    done
done

# Install Crystal dependencies
echo "Installing Crystal dependencies..."
shards install

# Show connection information
echo ""
echo "=== Development Environment Ready ==="
echo ""
echo "PostgreSQL:"
echo "  URL: postgres://mosquito:mosquito@localhost:5432/mosquito_dev"
echo "  Test URL: postgres://mosquito:mosquito@localhost:5433/mosquito_test"
echo ""
echo "Redis:"
echo "  URL: redis://localhost:6379"
echo ""
echo "To run tests:"
echo "  crystal spec                    # Run all tests with Redis backend"
echo "  ./scripts/test-postgres.sh      # Run PostgreSQL backend tests"
echo ""
echo "To stop services:"
echo "  docker-compose down"
echo ""