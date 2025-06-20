require "json"

module Mosquito::Api
  # Handles real-time event streaming for web dashboards
  # Provides both WebSocket and Server-Sent Events support
  module Realtime
    # Event stream handler that can be used with WebSocket or SSE
    class EventStream
      getter channel : Channel(Backend::BroadcastMessage)
      getter filters : Array(String)

      def initialize(@filters = ["mosquito:*"])
        @channel = Mosquito.backend.subscribe(filters.first)
      end

      # Process events and convert them to dashboard-friendly format
      def process_events(&block : String ->)
        spawn do
          loop do
            begin
              message = channel.receive
              processed_event = process_message(message)
              block.call(processed_event) if processed_event
            rescue ex
              Log.error(exception: ex) { "Error processing real-time event" }
              break
            end
          end
        end
      end

      private def process_message(message : Backend::BroadcastMessage) : String?
        return nil unless message.channel.starts_with?("mosquito:")

        begin
          data = JSON.parse(message.message)
          event_type = data["event"]?.try(&.as_s)

          return nil unless event_type

          dashboard_event = {
            "type"      => event_type,
            "timestamp" => Time.utc.to_unix,
            "channel"   => message.channel,
            "data"      => enhance_event_data(data, event_type),
          }

          dashboard_event.to_json
        rescue ex : JSON::ParseException
          Log.warn { "Failed to parse event message: #{message.message}" }
          nil
        end
      end

      private def enhance_event_data(data, event_type : String)
        enhanced = data.as_h.dup

        case event_type
        when "job-started", "job-finished"
          if job_run_id = data["job_run"]?.try(&.as_s)
            job_run = Api::JobRun.new(job_run_id)
            if job_run.found?
              enhanced["job_details"] = {
                "type"         => job_run.type,
                "queue_name"   => job_run.queue_name,
                "retry_count"  => job_run.retry_count,
                "enqueue_time" => job_run.enqueue_time.to_unix,
              }
            end
          end
        when "enqueued"
          if job_run_id = data["job_run"]?.try(&.as_s)
            job_run = Api::JobRun.new(job_run_id)
            if job_run.found?
              enhanced["job_details"] = {
                "type"       => job_run.type,
                "queue_name" => job_run.queue_name,
              }
            end
          end
        end

        enhanced
      end

      def close
        channel.close unless channel.closed?
      end
    end

    # Server-Sent Events handler
    class SSEHandler
      def self.handle(io : IO, filters : Array(String) = ["mosquito:*"])
        # Set SSE headers
        io << "Content-Type: text/event-stream\r\n"
        io << "Cache-Control: no-cache\r\n"
        io << "Connection: keep-alive\r\n"
        io << "Access-Control-Allow-Origin: *\r\n"
        io << "\r\n"
        io.flush

        stream = EventStream.new(filters)

        # Send initial connection event
        write_sse_event(io, "connected", {
          "message"   => "Connected to Mosquito event stream",
          "timestamp" => Time.utc.to_unix,
        }.to_json)

        # Process events
        stream.process_events do |event_json|
          write_sse_event(io, "mosquito-event", event_json)
        end

        # Cleanup
        stream.close
      end

      private def self.write_sse_event(io : IO, event_type : String, data : String)
        io << "event: #{event_type}\n"
        io << "data: #{data}\n"
        io << "\n"
        io.flush
      rescue ex
        Log.error(exception: ex) { "Failed to write SSE event" }
      end
    end

    # WebSocket handler
    class WebSocketHandler
      def self.handle(ws, filters : Array(String) = ["mosquito:*"])
        stream = EventStream.new(filters)

        # Send initial connection message
        ws.send({
          "type"      => "connected",
          "message"   => "Connected to Mosquito WebSocket",
          "timestamp" => Time.utc.to_unix,
        }.to_json)

        # Handle incoming messages (for potential filtering/commands)
        spawn do
          ws.on_message do |message|
            handle_websocket_message(ws, message, stream)
          end
        end

        # Process events
        stream.process_events do |event_json|
          ws.send(event_json)
        end

        # Cleanup
        stream.close
      end

      private def self.handle_websocket_message(ws, message : String, stream : EventStream)
        begin
          data = JSON.parse(message)
          case data["action"]?.try(&.as_s)
          when "ping"
            ws.send({
              "type"      => "pong",
              "timestamp" => Time.utc.to_unix,
            }.to_json)
          when "subscribe"
            # Handle subscription changes if needed
            # This could be extended to support dynamic filter changes
          end
        rescue ex : JSON::ParseException
          ws.send({
            "type"      => "error",
            "message"   => "Invalid JSON message",
            "timestamp" => Time.utc.to_unix,
          }.to_json)
        end
      rescue ex
        Log.error(exception: ex) { "Error handling WebSocket message" }
      end
    end

    # Event statistics aggregator for real-time dashboard updates
    class EventStats
      @events_count = Hash(String, Int32).new(0)
      @last_reset = Time.utc

      def initialize(@window : Time::Span = 1.minute)
      end

      def record_event(event_type : String)
        reset_if_needed
        @events_count[event_type] += 1
      end

      def get_stats : Hash(String, Int32)
        reset_if_needed
        @events_count.dup
      end

      def get_rate(event_type : String) : Float64
        reset_if_needed
        events = @events_count[event_type]? || 0
        elapsed = Time.utc - @last_reset
        return 0.0 if elapsed.total_seconds == 0
        events.to_f / elapsed.total_seconds
      end

      private def reset_if_needed
        if Time.utc - @last_reset > @window
          @events_count.clear
          @last_reset = Time.utc
        end
      end
    end
  end
end
