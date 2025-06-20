require "db"
require "pg"
require "json"

module Mosquito
  class PostgresBackend < Backend
    @@connection_url : String?
    @@db : DB::Database?

    # Common SQL queries as constants for better performance
    UPSERT_STORAGE_SQL = <<-SQL
      INSERT INTO mosquito_storage (key, data)
      VALUES ($1, $2::jsonb)
      ON CONFLICT (key) DO UPDATE
      SET data = $2::jsonb, updated_at = CURRENT_TIMESTAMP
    SQL

    UPSERT_FIELD_SQL = <<-SQL
      INSERT INTO mosquito_storage (key, data)
      VALUES ($1, jsonb_build_object($2::text, $3::text))
      ON CONFLICT (key) DO UPDATE
      SET data = mosquito_storage.data || jsonb_build_object($2::text, $3::text),
          updated_at = CURRENT_TIMESTAMP
    SQL

    def initialize(name : String | Symbol)
      super(name)
    end

    def self.connection_url=(url : String)
      # Close existing connection pool if URL changes
      @@db.try(&.close) if @@connection_url && @@connection_url != url
      @@connection_url = url
      @@db = nil
    end

    def self.connection_url
      @@connection_url ||= ENV["DATABASE_URL"]? || raise "PostgresBackend requires DATABASE_URL or explicit connection_url configuration"
    end

    def self.connection_pool : DB::Database
      # Build connection URL with pool parameters
      @@db ||= begin
        url = URI.parse(connection_url)
        params = url.query_params

        # Set pool configuration from environment or defaults
        params["initial_pool_size"] = ENV["MOSQUITO_PG_POOL_INITIAL"]? || "1"
        params["max_pool_size"] = ENV["MOSQUITO_PG_POOL_MAX"]? || "5"
        params["max_idle_pool_size"] = ENV["MOSQUITO_PG_POOL_IDLE"]? || "1"
        params["checkout_timeout"] = ENV["MOSQUITO_PG_TIMEOUT"]? || "5"
        params["retry_attempts"] = ENV["MOSQUITO_PG_RETRY"]? || "1"

        url.query_params = params
        DB.open(url.to_s)
      end
    end

    private def with_connection(&)
      self.class.connection_pool.using_connection do |conn|
        yield conn
      end
    end

    def self.with_connection(&)
      connection_pool.using_connection do |conn|
        yield conn
      end
    end

    module ClassMethods
      def store(key : String, value : Hash(String, String)) : Nil
        with_connection do |db|
          db.exec(UPSERT_STORAGE_SQL, key, value.to_json)
        end
      end

      def retrieve(key : String) : Hash(String, String)
        with_connection do |db|
          result = db.query_one?(<<-SQL, key, as: String)
            SELECT data::text FROM mosquito_storage WHERE key = $1
          SQL

          return {} of String => String unless result

          json = JSON.parse(result)
          hash = {} of String => String
          json.as_h.each do |k, v|
            hash[k] = v.as_s
          end
          hash
        end
      rescue
        {} of String => String
      end

      def list_queues : Array(String)
        with_connection do |db|
          db.query_all(<<-SQL, as: String)
            SELECT DISTINCT queue_name 
            FROM mosquito_queues 
            WHERE queue_type IN ('waiting', 'scheduled', 'pending')
            ORDER BY queue_name
          SQL
        end
      end

      def list_overseers : Array(String)
        prefix = build_key("overseer")
        with_connection do |db|
          db.query_all(<<-SQL, "#{prefix}:%", as: String)
            SELECT REPLACE(key, '#{prefix}:', '') 
            FROM mosquito_storage 
            WHERE key LIKE $1
            ORDER BY key
          SQL
        end
      end

      def register_overseer(id : String) : Nil
        store(build_key("overseer", id), {"id" => id})
      end

      def delete(key : String, in ttl : Int64 = 0) : Nil
        if ttl > 0
          delete(key, in: ttl.seconds)
        else
          with_connection do |db|
            db.exec("DELETE FROM mosquito_storage WHERE key = $1", key)
          end
        end
      end

      def delete(key : String, in ttl : Time::Span) : Nil
        with_connection do |db|
          db.exec(<<-SQL, key, Time.utc + ttl)
            UPDATE mosquito_storage 
            SET expires_at = $2 
            WHERE key = $1
          SQL
        end
      end

      def expires_in(key : String) : Int64
        with_connection do |db|
          expires_at = db.query_one?(<<-SQL, key, as: Time?)
            SELECT expires_at FROM mosquito_storage WHERE key = $1
          SQL

          return -1_i64 unless expires_at

          ttl = (expires_at - Time.utc).total_seconds.to_i64
          ttl > 0 ? ttl : -1_i64
        end
      rescue
        -1_i64
      end

      def get(key : String, field : String) : String?
        with_connection do |db|
          result = db.query_one?(<<-SQL, key, field, as: String?)
            SELECT data->>$2 
            FROM mosquito_storage 
            WHERE key = $1
          SQL

          result
        end
      rescue
        nil
      end

      def set(key : String, field : String, value : String) : String
        with_connection do |db|
          db.exec(UPSERT_FIELD_SQL, key, field, value)
        end
        value
      end

      def set(key : String, values : Hash(String, String?) | Hash(String, Nil) | Hash(String, String)) : Nil
        return if values.empty?

        with_connection do |db|
          # Separate nil and non-nil values
          non_nil_values = {} of String => String
          nil_keys = [] of String

          values.each do |k, v|
            if v.nil?
              nil_keys << k
            else
              non_nil_values[k] = v.to_s
            end
          end

          # If we have non-nil values, insert/update them
          if !non_nil_values.empty?
            db.exec(<<-SQL, key, non_nil_values.to_json)
              INSERT INTO mosquito_storage (key, data)
              VALUES ($1, $2::jsonb)
              ON CONFLICT (key) DO UPDATE
              SET data = mosquito_storage.data || $2::jsonb,
                  updated_at = CURRENT_TIMESTAMP
            SQL
          end

          # Remove nil keys
          nil_keys.each do |nil_key|
            delete_field(key, nil_key)
          end
        end
      end

      def delete_field(key : String, field : String) : Nil
        with_connection do |db|
          db.exec(<<-SQL, key, field)
            UPDATE mosquito_storage
            SET data = data - $2,
                updated_at = CURRENT_TIMESTAMP
            WHERE key = $1
          SQL
        end
      end

      def increment(key : String, field : String) : Int64
        increment(key, field, 1)
      end

      def increment(key : String, field : String, by value : Int32) : Int64
        with_connection do |db|
          new_value = 0_i64

          # Use a transaction to ensure atomicity
          db.transaction do |tx|
            conn = tx.connection

            # Get current value or 0
            current_result = conn.query_one?(<<-SQL, key, field, as: String?)
              SELECT data->>$2 FROM mosquito_storage WHERE key = $1
            SQL

            current = 0_i64
            if current_result
              current = current_result.to_i64? || 0_i64
            end

            new_value = current + value

            # Update or insert the new value
            conn.exec(<<-SQL, key, field, new_value.to_s)
              INSERT INTO mosquito_storage (key, data)
              VALUES ($1, jsonb_build_object($2::text, $3::text))
              ON CONFLICT (key) DO UPDATE
              SET data = mosquito_storage.data || jsonb_build_object($2::text, $3::text),
                  updated_at = CURRENT_TIMESTAMP
            SQL
          end

          new_value
        end
      end

      def flush : Nil
        with_connection do |db|
          db.exec("TRUNCATE mosquito_storage, mosquito_queues, mosquito_locks, mosquito_notifications")
        end
      end

      # Clean up expired entries - useful for periodic maintenance
      def cleanup_expired : Int32
        with_connection do |db|
          storage_deleted = db.exec("DELETE FROM mosquito_storage WHERE expires_at IS NOT NULL AND expires_at < CURRENT_TIMESTAMP")
          locks_deleted = db.exec("DELETE FROM mosquito_locks WHERE expires_at < CURRENT_TIMESTAMP")

          storage_deleted.rows_affected.to_i32 + locks_deleted.rows_affected.to_i32
        end
      end

      def lock?(key : String, value : String, ttl : Time::Span) : Bool
        with_connection do |db|
          # First, clean up any expired locks
          db.exec("DELETE FROM mosquito_locks WHERE expires_at < CURRENT_TIMESTAMP")

          # Try to acquire or update the lock
          result = db.exec(<<-SQL, key, value, Time.utc + ttl, value, Time.utc + ttl)
            INSERT INTO mosquito_locks (key, value, expires_at)
            VALUES ($1, $2, $3)
            ON CONFLICT (key) DO UPDATE
            SET expires_at = $5
            WHERE mosquito_locks.value = $4
          SQL

          # If we affected a row, we have the lock
          if result.rows_affected > 0
            true
          else
            # Check if someone else has the lock
            existing = db.query_one?(<<-SQL, key, as: {String, Time})
              SELECT value, expires_at FROM mosquito_locks WHERE key = $1
            SQL

            # No lock exists (it might have been cleaned up)
            existing.nil?
          end
        end
      end

      def unlock(key : String, value : String) : Nil
        with_connection do |db|
          db.exec(<<-SQL, key, value)
            DELETE FROM mosquito_locks 
            WHERE key = $1 AND value = $2
          SQL
        end
      end

      def publish(key : String, value : String) : Nil
        with_connection do |db|
          # Insert into notifications table
          db.exec(<<-SQL, key, value)
            INSERT INTO mosquito_notifications (channel, message)
            VALUES ($1, $2)
          SQL

          # Send PostgreSQL NOTIFY (payload must be quoted)
          # Use | as delimiter since keys might contain :
          payload = "#{key}|#{value}".gsub("'", "''") # Escape single quotes
          db.exec("NOTIFY mosquito_pubsub, '#{payload}'")
        end
      end

      def subscribe(key : String) : Channel(BroadcastMessage)
        channel = Channel(BroadcastMessage).new(32)

        spawn do
          begin
            # Use PG.connect_listen with non-blocking mode
            listen_conn = PG.connect_listen(connection_url, "mosquito_pubsub", blocking: false) do |notification|
              if notification && notification.payload
                Log.debug { "PostgreSQL notification received: #{notification.payload}" }
                parts = notification.payload.split("|", 2)
                if parts.size == 2 && parts[0] == key
                  message = BroadcastMessage.new(parts[0], parts[1])
                  begin
                    channel.send(message) unless channel.closed?
                  rescue Channel::ClosedError
                    # Channel was closed, ignore
                  end
                end
              end
            end

            # Keep the connection alive until channel is closed
            loop do
              break if channel.closed?
              sleep 0.1.seconds
            end

            listen_conn.close
          rescue ex
            Log.error(exception: ex) { "Error in PostgreSQL subscribe: #{ex.message}" }
          ensure
            channel.close unless channel.closed?
          end
        end

        channel
      end
    end

    extend ClassMethods

    def enqueue(job_run : JobRun) : JobRun
      with_connection do |db|
        db.exec(<<-SQL, @name, job_run.id)
          INSERT INTO mosquito_queues (queue_name, queue_type, job_data)
          VALUES ($1, 'waiting', $2)
        SQL
      end
      job_run
    end

    # Batch enqueue for better performance when enqueueing multiple jobs
    def enqueue_batch(job_runs : Array(JobRun)) : Array(JobRun)
      return [] of JobRun if job_runs.empty?

      with_connection do |db|
        db.transaction do |tx|
          conn = tx.connection
          job_runs.each do |job_run|
            conn.exec(<<-SQL, @name, job_run.id)
              INSERT INTO mosquito_queues (queue_name, queue_type, job_data)
              VALUES ($1, 'waiting', $2)
            SQL
          end
        end
      end
      job_runs
    end

    def dequeue : JobRun?
      with_connection do |db|
        db.transaction do |tx|
          conn = tx.connection

          # First, check scheduled jobs that are ready
          scheduled = conn.query_one?(<<-SQL, @name, Time.utc, as: {Int64, String})
            SELECT id, job_data 
            FROM mosquito_queues 
            WHERE queue_name = $1 
              AND queue_type = 'scheduled' 
              AND scheduled_at <= $2
            ORDER BY scheduled_at 
            LIMIT 1
            FOR UPDATE SKIP LOCKED
          SQL

          if scheduled
            # Move from scheduled to pending
            conn.exec(<<-SQL, scheduled[0])
              UPDATE mosquito_queues 
              SET queue_type = 'pending', scheduled_at = NULL
              WHERE id = $1
            SQL

            return JobRun.retrieve(scheduled[1]) if job_run = JobRun.retrieve(scheduled[1])
          end

          # Otherwise, get from waiting queue
          waiting = conn.query_one?(<<-SQL, @name, as: {Int64, String})
            SELECT id, job_data 
            FROM mosquito_queues 
            WHERE queue_name = $1 
              AND queue_type = 'waiting'
            ORDER BY created_at 
            LIMIT 1
            FOR UPDATE SKIP LOCKED
          SQL

          if waiting
            # Move from waiting to pending
            conn.exec(<<-SQL, waiting[0])
              UPDATE mosquito_queues 
              SET queue_type = 'pending'
              WHERE id = $1
            SQL

            return JobRun.retrieve(waiting[1]) if job_run = JobRun.retrieve(waiting[1])
          end

          nil
        end
      end
    end

    def schedule(job_run : JobRun, at scheduled_time : Time) : JobRun
      with_connection do |db|
        db.exec(<<-SQL, @name, job_run.id, scheduled_time)
          INSERT INTO mosquito_queues (queue_name, queue_type, job_data, scheduled_at)
          VALUES ($1, 'scheduled', $2, $3)
        SQL
      end
      job_run
    end

    def deschedule : Array(JobRun)
      jobs = [] of JobRun

      with_connection do |db|
        db.transaction do |tx|
          conn = tx.connection

          # Get all scheduled jobs that are ready
          ready_jobs = conn.query_all(<<-SQL, @name, Time.utc, as: {Int64, String})
            SELECT id, job_data 
            FROM mosquito_queues 
            WHERE queue_name = $1 
              AND queue_type = 'scheduled' 
              AND scheduled_at <= $2
            ORDER BY scheduled_at
            FOR UPDATE
          SQL

          ready_jobs.each do |id, job_data|
            # Move to waiting queue
            conn.exec(<<-SQL, id)
              UPDATE mosquito_queues 
              SET queue_type = 'waiting', scheduled_at = NULL
              WHERE id = $1
            SQL

            if job_run = JobRun.retrieve(job_data)
              jobs << job_run
            end
          end
        end
      end

      jobs
    end

    def finish(job_run : JobRun)
      with_connection do |db|
        db.exec(<<-SQL, @name, job_run.id)
          DELETE FROM mosquito_queues 
          WHERE queue_name = $1 
            AND queue_type = 'pending' 
            AND job_data = $2
        SQL
      end
    end

    def terminate(job_run : JobRun)
      with_connection do |db|
        db.transaction do |tx|
          conn = tx.connection

          # First delete from pending
          result = conn.exec(<<-SQL, @name, job_run.id)
            DELETE FROM mosquito_queues 
            WHERE queue_name = $1 
              AND queue_type = 'pending' 
              AND job_data = $2
          SQL

          # If we deleted something, add to dead queue
          if result.rows_affected > 0
            conn.exec(<<-SQL, @name, job_run.id)
              INSERT INTO mosquito_queues (queue_name, queue_type, job_data)
              VALUES ($1, 'dead', $2)
            SQL
          end
        end
      end
    end

    def flush : Nil
      with_connection do |db|
        db.exec(<<-SQL, @name)
          DELETE FROM mosquito_queues WHERE queue_name = $1
        SQL
      end
    end

    def size(include_dead = true) : Int64
      with_connection do |db|
        if include_dead
          db.query_one(<<-SQL, @name, as: Int64)
            SELECT COUNT(*) FROM mosquito_queues WHERE queue_name = $1
          SQL
        else
          db.query_one(<<-SQL, @name, as: Int64)
            SELECT COUNT(*) FROM mosquito_queues 
            WHERE queue_name = $1 AND queue_type != 'dead'
          SQL
        end
      end
    end

    def scheduled_job_run_time(job_run : JobRun) : String?
      with_connection do |db|
        result = db.query_one?(<<-SQL, @name, job_run.id, as: Time?)
          SELECT scheduled_at 
          FROM mosquito_queues 
          WHERE queue_name = $1 
            AND queue_type = 'scheduled' 
            AND job_data = $2
        SQL

        result ? result.to_rfc3339 : nil
      end
    end

    def dump_waiting_q : Array(String)
      dump_queue("waiting")
    end

    def dump_scheduled_q : Array(String)
      dump_queue("scheduled")
    end

    def dump_pending_q : Array(String)
      dump_queue("pending")
    end

    def dump_dead_q : Array(String)
      dump_queue("dead")
    end

    private def dump_queue(queue_type : String) : Array(String)
      with_connection do |db|
        order_by = case queue_type
                   when "scheduled"
                     "scheduled_at"
                   when "dead"
                     "created_at DESC"
                   else
                     "created_at"
                   end

        db.query_all(<<-SQL, @name, queue_type, as: String)
          SELECT job_data 
          FROM mosquito_queues 
          WHERE queue_name = $1 AND queue_type = $2
          ORDER BY #{order_by}
        SQL
      end
    end

    # Size methods for each queue type
    def waiting_size : Int64
      queue_size("waiting")
    end

    def scheduled_size : Int64
      queue_size("scheduled")
    end

    def pending_size : Int64
      queue_size("pending")
    end

    def dead_size : Int64
      queue_size("dead")
    end

    private def queue_size(queue_type : String) : Int64
      with_connection do |db|
        db.query_one(<<-SQL, @name, queue_type, as: Int64)
          SELECT COUNT(*) 
          FROM mosquito_queues 
          WHERE queue_name = $1 AND queue_type = $2
        SQL
      end
    end
  end
end
