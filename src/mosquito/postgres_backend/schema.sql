-- Mosquito PostgreSQL Backend Schema

-- Key-value storage table for general data (metadata, job data, etc.)
CREATE TABLE IF NOT EXISTS mosquito_storage (
    key VARCHAR(255) PRIMARY KEY,
    data JSONB NOT NULL DEFAULT '{}',
    expires_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Index for expiration cleanup
CREATE INDEX IF NOT EXISTS idx_mosquito_storage_expires_at ON mosquito_storage(expires_at) WHERE expires_at IS NOT NULL;

-- Queue tables for different job states
CREATE TABLE IF NOT EXISTS mosquito_queues (
    id BIGSERIAL PRIMARY KEY,
    queue_name VARCHAR(255) NOT NULL,
    queue_type VARCHAR(50) NOT NULL CHECK (queue_type IN ('waiting', 'scheduled', 'pending', 'dead')),
    job_data TEXT NOT NULL,
    scheduled_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create a partial unique index instead of constraint with WHERE clause
CREATE UNIQUE INDEX IF NOT EXISTS unique_pending_job 
ON mosquito_queues(queue_name, queue_type, job_data) 
WHERE queue_type = 'pending';

-- Indexes for efficient queue operations
CREATE INDEX IF NOT EXISTS idx_mosquito_queues_waiting ON mosquito_queues(queue_name, created_at) WHERE queue_type = 'waiting';
CREATE INDEX IF NOT EXISTS idx_mosquito_queues_scheduled ON mosquito_queues(queue_name, scheduled_at) WHERE queue_type = 'scheduled';
CREATE INDEX IF NOT EXISTS idx_mosquito_queues_pending ON mosquito_queues(queue_name) WHERE queue_type = 'pending';
CREATE INDEX IF NOT EXISTS idx_mosquito_queues_dead ON mosquito_queues(queue_name, created_at DESC) WHERE queue_type = 'dead';

-- Distributed locks table
CREATE TABLE IF NOT EXISTS mosquito_locks (
    key VARCHAR(255) PRIMARY KEY,
    value VARCHAR(255) NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Index for lock expiration
CREATE INDEX IF NOT EXISTS idx_mosquito_locks_expires_at ON mosquito_locks(expires_at);

-- Pub/Sub notifications table (for LISTEN/NOTIFY)
CREATE TABLE IF NOT EXISTS mosquito_notifications (
    id BIGSERIAL PRIMARY KEY,
    channel VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Trigger for updating updated_at on mosquito_storage
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_mosquito_storage_updated_at BEFORE UPDATE ON mosquito_storage
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to clean up expired entries
CREATE OR REPLACE FUNCTION cleanup_expired_entries() RETURNS void AS $$
BEGIN
    DELETE FROM mosquito_storage WHERE expires_at IS NOT NULL AND expires_at < CURRENT_TIMESTAMP;
    DELETE FROM mosquito_locks WHERE expires_at < CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;