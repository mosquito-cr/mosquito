#!/usr/bin/env crystal

# Web Server Example for Mosquito Dashboard
# This example shows how to create a complete HTTP API server
# for a Mosquito dashboard using Crystal's HTTP::Server

require "http/server"
require "json"
require "../src/mosquito"

# Configure Mosquito
Mosquito.configure do |settings|
  settings.redis_url = ENV["REDIS_URL"]? || "redis://localhost:6379/0"
  settings.publish_metrics = true
end

# HTTP API Routes
def handle_request(context : HTTP::Server::Context)
  request = context.request
  response = context.response
  
  # Set CORS headers for web dashboard access
  response.headers["Access-Control-Allow-Origin"] = "*"
  response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
  response.headers["Access-Control-Allow-Headers"] = "Content-Type"
  response.content_type = "application/json"

  # Handle preflight requests
  if request.method == "OPTIONS"
    response.status_code = 200
    return
  end

  begin
    case {request.method, request.path}
    
    # Dashboard overview
    when {"GET", "/api/dashboard"}
      data = Mosquito::Api::WebInterface.dashboard_overview
      response.print Mosquito::Api::WebInterface.json_response(data)
    
    # Queue listing
    when {"GET", "/api/queues"}
      data = Mosquito::Api::WebInterface.queues_index
      response.print Mosquito::Api::WebInterface.json_response(data)
    
    # Specific queue details
    when {"GET", path} if path.starts_with?("/api/queues/") && !path.ends_with?("/")
      queue_name = path.split("/").last
      data = Mosquito::Api::WebInterface.queue_details(queue_name)
      response.print Mosquito::Api::WebInterface.json_response(data)
    
    # Worker status
    when {"GET", "/api/workers"}
      data = Mosquito::Api::WebInterface.workers_index
      response.print Mosquito::Api::WebInterface.json_response(data)
    
    # Job details
    when {"GET", path} if path.starts_with?("/api/jobs/") && !path.includes?("?")
      job_id = path.split("/").last
      data = Mosquito::Api::WebInterface.job_details(job_id)
      response.print Mosquito::Api::WebInterface.json_response(data)
    
    # Jobs by state with query parameters
    when {"GET", "/api/jobs"}
      query = request.query_params
      state = query["state"]? || "waiting"
      queue_name = query["queue"]?
      page = query["page"]?.try(&.to_i?) || 1
      per_page = query["per_page"]?.try(&.to_i?) || 50
      
      data = Mosquito::Api::WebInterface.jobs_by_state(state, queue_name, page, per_page)
      response.print Mosquito::Api::WebInterface.json_response(data)
    
    # Metrics
    when {"GET", "/api/metrics"}
      query = request.query_params
      queue_name = query["queue"]?
      job_type = query["job_type"]?
      
      data = Mosquito::Api::WebInterface.metrics(queue_name, job_type)
      response.print Mosquito::Api::WebInterface.json_response(data)
    
    # Health check
    when {"GET", "/api/health"}
      data = Mosquito::Api::WebInterface.health_check
      response.print Mosquito::Api::WebInterface.json_response(data)
    
    # Statistics summary
    when {"GET", "/api/stats"}
      data = Mosquito::Api::WebInterface.stats_summary
      response.print Mosquito::Api::WebInterface.json_response(data)
    
    # Real-time events info
    when {"GET", "/api/events"}
      data = Mosquito::Api::WebInterface.events_stream
      response.print Mosquito::Api::WebInterface.json_response(data)
    
    # Server-Sent Events stream
    when {"GET", "/api/events/stream"}
      filters = request.query_params["filters"]?.try(&.split(",")) || ["mosquito:*"]
      Mosquito::Api::Realtime::SSEHandler.handle(response, filters)
      return  # SSE handler manages the response
    
    # WebSocket endpoint (placeholder - needs WebSocket server setup)
    when {"GET", "/api/events/ws"}
      response.status_code = 501
      response.print Mosquito::Api::WebInterface.error_response(
        "WebSocket endpoint requires WebSocket server setup. See documentation for implementation details.",
        "not_implemented",
        501
      )
    
    # API documentation
    when {"GET", "/api"}
      documentation = {
        "name" => "Mosquito Dashboard API",
        "version" => "1.0",
        "description" => "REST API for Mosquito job queue monitoring and management",
        "endpoints" => {
          "GET /api/dashboard" => "Dashboard overview with global stats and queue summary",
          "GET /api/queues" => "List all queues with basic statistics",
          "GET /api/queues/:name" => "Detailed information for a specific queue",
          "GET /api/workers" => "List all active workers (overseers and executors)",
          "GET /api/jobs/:id" => "Details for a specific job run",
          "GET /api/jobs?state=:state&queue=:queue&page=:page&per_page=:per_page" => "List jobs by state with pagination",
          "GET /api/metrics?queue=:queue&job_type=:job_type" => "Performance metrics",
          "GET /api/health" => "System health check",
          "GET /api/stats" => "Comprehensive statistics summary",
          "GET /api/events" => "Real-time events connection information",
          "GET /api/events/stream" => "Server-Sent Events stream for real-time updates"
        },
        "real_time" => {
          "sse" => "/api/events/stream",
          "websocket" => "/api/events/ws (requires WebSocket setup)"
        }
      }
      response.print Mosquito::Api::WebInterface.json_response(documentation)
    
    # Basic health check
    when {"GET", "/health"}
      response.print %({"status": "ok", "service": "mosquito-dashboard-api"})
    
    # Serve a simple dashboard HTML page
    when {"GET", "/"}
      response.content_type = "text/html"
      response.print DASHBOARD_HTML
    
    else
      response.status_code = 404
      response.print Mosquito::Api::WebInterface.error_response(
        "Endpoint not found",
        "not_found",
        404
      )
    end
    
  rescue ex : Exception
    response.status_code = 500
    response.print Mosquito::Api::WebInterface.error_response(
      "Internal server error: #{ex.message}",
      "internal_error",
      500
    )
  end
end

# Simple HTML dashboard for demonstration
DASHBOARD_HTML = <<-HTML
<!DOCTYPE html>
<html>
<head>
    <title>Mosquito Dashboard</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .container { max-width: 1200px; margin: 0 auto; }
        .card { border: 1px solid #ddd; padding: 20px; margin: 10px 0; border-radius: 5px; }
        .metric { display: inline-block; margin: 10px 20px 10px 0; }
        .metric-value { font-size: 24px; font-weight: bold; color: #333; }
        .metric-label { font-size: 12px; color: #666; }
        .queue-list { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 15px; }
        .queue-card { border: 1px solid #eee; padding: 15px; border-radius: 5px; }
        .health-healthy { color: green; }
        .health-warning { color: orange; }
        .health-unhealthy { color: red; }
        #events { background: #f5f5f5; padding: 10px; border-radius: 5px; height: 200px; overflow-y: auto; font-family: monospace; font-size: 12px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Mosquito Dashboard</h1>
        
        <div class="card">
            <h2>System Overview</h2>
            <div id="overview">Loading...</div>
        </div>
        
        <div class="card">
            <h2>Queues</h2>
            <div id="queues" class="queue-list">Loading...</div>
        </div>
        
        <div class="card">
            <h2>Workers</h2>
            <div id="workers">Loading...</div>
        </div>
        
        <div class="card">
            <h2>Real-time Events</h2>
            <div id="events"></div>
        </div>
    </div>

    <script>
        // Fetch and display overview data
        function updateOverview() {
            fetch('/api/dashboard')
                .then(response => response.json())
                .then(data => {
                    const overview = data.data;
                    const stats = overview.global_stats;
                    const health = overview.cluster_health;
                    
                    document.getElementById('overview').innerHTML = `
                        <div class="metric">
                            <div class="metric-value">${stats.total_jobs}</div>
                            <div class="metric-label">Total Jobs</div>
                        </div>
                        <div class="metric">
                            <div class="metric-value">${stats.active_executors}</div>
                            <div class="metric-label">Active Executors</div>
                        </div>
                        <div class="metric">
                            <div class="metric-value">${stats.busy_executors}</div>
                            <div class="metric-label">Busy Executors</div>
                        </div>
                        <div class="metric">
                            <div class="metric-value health-${health}">${health.toUpperCase()}</div>
                            <div class="metric-label">System Health</div>
                        </div>
                    `;
                });
        }
        
        // Fetch and display queues
        function updateQueues() {
            fetch('/api/queues')
                .then(response => response.json())
                .then(data => {
                    const queues = data.data.queues;
                    const queueHtml = queues.map(queue => `
                        <div class="queue-card">
                            <h3>${queue.name}</h3>
                            <div><strong>Total:</strong> ${queue.total_size}</div>
                            <div><strong>Waiting:</strong> ${queue.size_details.waiting}</div>
                            <div><strong>Pending:</strong> ${queue.size_details.pending}</div>
                            <div><strong>Dead:</strong> ${queue.size_details.dead}</div>
                        </div>
                    `).join('');
                    
                    document.getElementById('queues').innerHTML = queueHtml || '<p>No queues found</p>';
                });
        }
        
        // Fetch and display workers
        function updateWorkers() {
            fetch('/api/workers')
                .then(response => response.json())
                .then(data => {
                    const overseers = data.data.overseers;
                    const workerHtml = overseers.map(overseer => `
                        <div><strong>Overseer:</strong> ${overseer.instance_id}</div>
                        <div><strong>Executors:</strong> ${overseer.executors.length}</div>
                    `).join('') || '<p>No active workers</p>';
                    
                    document.getElementById('workers').innerHTML = workerHtml;
                });
        }
        
        // Connect to real-time events
        function connectToEvents() {
            const eventsDiv = document.getElementById('events');
            const eventSource = new EventSource('/api/events/stream');
            
            eventSource.onmessage = function(event) {
                const data = JSON.parse(event.data);
                const timestamp = new Date().toLocaleTimeString();
                eventsDiv.innerHTML += `[${timestamp}] ${data.type}: ${JSON.stringify(data.data)}\n`;
                eventsDiv.scrollTop = eventsDiv.scrollHeight;
            };
            
            eventSource.onerror = function(event) {
                eventsDiv.innerHTML += '[ERROR] Connection to events stream failed\n';
            };
        }
        
        // Initial load and setup refresh
        updateOverview();
        updateQueues();
        updateWorkers();
        connectToEvents();
        
        // Refresh every 5 seconds
        setInterval(() => {
            updateOverview();
            updateQueues();
            updateWorkers();
        }, 5000);
    </script>
</body>
</html>
HTML

# Start the server
port = ENV["PORT"]?.try(&.to_i?) || 3000
host = ENV["HOST"]? || "0.0.0.0"

server = HTTP::Server.new do |context|
  handle_request(context)
end

puts "Starting Mosquito Dashboard API Server"
puts "Listening on http://#{host}:#{port}"
puts "Dashboard: http://#{host}:#{port}/"
puts "API Documentation: http://#{host}:#{port}/api"
puts "Press Ctrl+C to stop"

server.bind_tcp host, port
server.listen