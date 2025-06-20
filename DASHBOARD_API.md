# Mosquito Dashboard API

The Mosquito Dashboard API provides comprehensive monitoring and management capabilities for Mosquito job queues, similar to Sidekiq's web interface. This API enables you to build powerful web dashboards, monitoring tools, and administrative interfaces.

## Features

### 📊 Comprehensive Monitoring
- **Queue Statistics**: Real-time queue sizes, job counts by state
- **Worker Monitoring**: Active overseers and executors status
- **Job Tracking**: Individual job details, parameters, and execution history
- **System Health**: Cluster health metrics and performance indicators

### 📈 Performance Metrics
- **Historical Data**: Job success/failure rates, average execution times
- **Throughput Tracking**: Jobs processed per hour, queue utilization
- **Performance Analytics**: Executor utilization, processing rates
- **Custom Metrics**: Per-queue and per-job-type statistics

### ⚡ Real-time Updates
- **Event Streaming**: WebSocket and Server-Sent Events support
- **Live Monitoring**: Real-time job starts, completions, and failures
- **Worker Events**: Executor creation, termination, and heartbeats
- **System Events**: Queue changes, overseer status updates

## Quick Start

### 1. Enable Metrics Tracking

```crystal
require "mosquito"

Mosquito.configure do |settings|
  settings.redis_url = "redis://localhost:6379/0"
  settings.publish_metrics = true  # Enable metrics collection
end
```

### 2. Access Dashboard Data

```crystal
# Get comprehensive dashboard overview
overview = Mosquito::Api::WebInterface.dashboard_overview

# List all queues with statistics
queues = Mosquito::Api::WebInterface.queues_index

# Get detailed queue information
queue_details = Mosquito::Api::WebInterface.queue_details("my_queue")

# Monitor active workers
workers = Mosquito::Api::WebInterface.workers_index

# Check system health
health = Mosquito::Api::WebInterface.health_check
```

### 3. Real-time Event Monitoring

```crystal
# Server-Sent Events stream
Mosquito::Api::Realtime::SSEHandler.handle(io, ["mosquito:*"])

# WebSocket connection
stream = Mosquito::Api::Realtime::EventStream.new
stream.process_events do |event_json|
  puts "Event: #{event_json}"
end
```

## API Reference

### Core API Classes

#### `Mosquito::Api`
Main API namespace with factory methods:

```crystal
# Get API objects
overseer = Mosquito::Api.overseer("overseer_id")
executor = Mosquito::Api.executor("executor_id") 
job_run = Mosquito::Api.job_run("job_id")
queue = Mosquito::Api.queue("queue_name")

# List objects
overseers = Mosquito::Api.list_overseers
executors = Mosquito::Api.list_executors
queues = Mosquito::Api.list_queues

# Get statistics
global_stats = Mosquito::Api.global_stats
cluster_stats = Mosquito::Api.cluster_stats
queue_stats = Mosquito::Api.queue_stats

# Query jobs by state
waiting_jobs = Mosquito::Api.job_runs_by_state("waiting", "queue_name", 50)
```

#### `Mosquito::Api::WebInterface`
Web-friendly JSON API methods:

```crystal
# Dashboard endpoints
dashboard_overview()           # Complete dashboard overview
queues_index()                # Queue listing with stats
queue_details(name)           # Detailed queue information
workers_index()               # Active workers status
job_details(job_id)           # Individual job information
jobs_by_state(state, queue?, page?, per_page?)  # Paginated job listing
metrics(queue?, job_type?)    # Performance metrics
health_check()                # System health status
stats_summary()               # Statistics summary
events_stream()               # Real-time events info

# Response helpers
json_response(data)           # Wrap data in API response format
error_response(message, code, status)  # Standard error responses
```

#### `Mosquito::Api::Stats`
Statistics and analytics classes:

```crystal
# Global statistics
global_stats = Mosquito::Api::GlobalStats.new
puts global_stats.total_jobs
puts global_stats.active_executors
puts global_stats.processing_rate

# Queue-specific statistics  
queue = Mosquito::Api::Queue.new("my_queue")
queue_stats = Mosquito::Api::QueueStats.new(queue)
puts queue_stats.waiting_count
puts queue_stats.processing_rate

# Cluster health metrics
cluster_stats = Mosquito::Api::ClusterStats.new
puts cluster_stats.health_status        # "healthy", "warning", "unhealthy"
puts cluster_stats.executor_utilization # Percentage
puts cluster_stats.dead_jobs_ratio     # Ratio of failed jobs
```

#### `Mosquito::Api::Metrics`
Performance metrics tracking:

```crystal
# Track job lifecycle events (automatically handled by observability)
Mosquito::Api::Metrics.increment_enqueued("queue", "JobType")
Mosquito::Api::Metrics.increment_finished("queue", "JobType", duration_ms)
Mosquito::Api::Metrics.increment_failed("queue", "JobType")

# Query metrics
enqueued_count = Mosquito::Api::Metrics.get_enqueued_count("queue", "JobType")
success_rate = Mosquito::Api::Metrics.get_success_rate("queue", "JobType")
avg_duration = Mosquito::Api::Metrics.get_average_duration("queue", "JobType")
throughput = Mosquito::Api::Metrics.get_throughput("queue")

# Get comprehensive metrics
queue_metrics = Mosquito::Api::Metrics.queue_metrics("queue")
job_metrics = Mosquito::Api::Metrics.job_type_metrics("queue", "JobType")
global_metrics = Mosquito::Api::Metrics.global_metrics
```

#### `Mosquito::Api::Realtime`
Real-time event streaming:

```crystal
# Event stream processing
stream = Mosquito::Api::Realtime::EventStream.new(["mosquito:*"])
stream.process_events do |event_json|
  # Handle real-time events
  event = JSON.parse(event_json)
  puts "#{event["type"]}: #{event["data"]}"
end

# Server-Sent Events handler
Mosquito::Api::Realtime::SSEHandler.handle(io) do |event|
  # Stream events to HTTP clients
end

# WebSocket handler
Mosquito::Api::Realtime::WebSocketHandler.handle(websocket) do |event|
  # Stream events to WebSocket clients  
end

# Event statistics
event_stats = Mosquito::Api::Realtime::EventStats.new(1.minute)
event_stats.record_event("job-started")
rate = event_stats.get_rate("job-started")
```

### Enhanced API Objects

#### `Mosquito::Api::Queue`
Enhanced queue inspection with detailed metrics:

```crystal
queue = Mosquito::Api::Queue.new("my_queue")

# Basic information
queue.name                    # Queue name
queue.size                    # Operating size (excluding dead jobs)
queue.total_size             # Total size including all states

# State-specific sizes
queue.waiting_size           # Jobs ready to be processed
queue.scheduled_size         # Jobs scheduled for future execution
queue.pending_size           # Jobs currently being processed
queue.dead_size              # Failed jobs

# Job collections by state
queue.waiting_job_runs       # Array of waiting JobRun objects
queue.scheduled_job_runs     # Array of scheduled JobRun objects  
queue.pending_job_runs       # Array of pending JobRun objects
queue.dead_job_runs          # Array of dead JobRun objects

# Detailed size breakdown
queue.size_details           # Hash with all state counts
```

#### `Mosquito::Api::JobRun`
Enhanced job run inspection with execution details:

```crystal
job_run = Mosquito::Api::JobRun.new("job_id")

# Basic information
job_run.id                   # Job run ID
job_run.type                 # Job class name
job_run.found?               # Does the job exist?

# Timing information
job_run.enqueue_time         # When job was enqueued
job_run.started_at           # When execution started (if started)
job_run.finished_at          # When execution finished (if finished)
job_run.duration             # Execution duration (if finished)

# Execution details
job_run.retry_count          # Number of retries
job_run.runtime_parameters   # Job parameters (excluding metadata)
job_run.queue_name           # Queue the job belongs to

# State checking
job_run.state                # "queued", "running", "finished"
job_run.successful?          # Job completed successfully
job_run.failed?              # Job failed
job_run.dead?                # Job is in dead queue

# JSON serialization
job_run.to_h                 # Hash representation for API responses
```

#### `Mosquito::Api::Overseer`
Worker management and monitoring:

```crystal
overseer = Mosquito::Api::Overseer.new("overseer_id")

# Basic information
overseer.instance_id         # Unique overseer identifier
overseer.last_heartbeat      # Last heartbeat timestamp

# Managed executors
overseer.executors           # Array of Executor objects

# List all overseers
overseers = Mosquito::Api::Overseer.all
```

#### `Mosquito::Api::Executor`
Individual worker monitoring:

```crystal
executor = Mosquito::Api::Executor.new("executor_id")

# Current status
executor.instance_id         # Unique executor identifier
executor.current_job         # Job ID being processed (if any)
executor.current_job_queue   # Queue of current job (if any)
executor.heartbeat           # Last heartbeat timestamp

# Check if executor is busy
busy = !executor.current_job.nil?
```

## HTTP API Server Example

Create a complete HTTP API server:

```crystal
require "http/server"
require "mosquito"

# Configure Mosquito with metrics enabled
Mosquito.configure do |settings|
  settings.redis_url = ENV["REDIS_URL"]? || "redis://localhost:6379/0"
  settings.publish_metrics = true
end

# Create HTTP server
server = HTTP::Server.new do |context|
  request = context.request
  response = context.response
  
  # Set CORS and content type
  response.headers["Access-Control-Allow-Origin"] = "*"
  response.content_type = "application/json"
  
  case {request.method, request.path}
  when {"GET", "/api/dashboard"}
    data = Mosquito::Api::WebInterface.dashboard_overview
    response.print Mosquito::Api::WebInterface.json_response(data)
    
  when {"GET", "/api/queues"}
    data = Mosquito::Api::WebInterface.queues_index
    response.print Mosquito::Api::WebInterface.json_response(data)
    
  when {"GET", "/api/health"}
    data = Mosquito::Api::WebInterface.health_check
    response.print Mosquito::Api::WebInterface.json_response(data)
    
  when {"GET", "/api/events/stream"}
    # Server-Sent Events for real-time updates
    Mosquito::Api::Realtime::SSEHandler.handle(response)
    return
    
  else
    response.status_code = 404
    response.print Mosquito::Api::WebInterface.error_response("Not found", "not_found", 404)
  end
end

# Start server
server.bind_tcp "0.0.0.0", 3000
server.listen
```

## Real-time Events

The API provides real-time event streaming for live dashboard updates:

### Event Types

- `job-started`: Job execution began
- `job-finished`: Job execution completed  
- `enqueued`: Job added to queue
- `dequeued`: Job removed from queue
- `executor-created`: New executor started
- `executor-died`: Executor terminated
- `overseer-starting`: Overseer initialization
- `overseer-stopping`: Overseer shutdown
- `overseer-stopped`: Overseer fully stopped

### Event Data Format

```json
{
  "type": "job-started",
  "timestamp": 1640995200,
  "channel": "mosquito:executor:12345",
  "data": {
    "event": "job-started",
    "job_run": "job_abc123",
    "from_queue": "default",
    "job_details": {
      "type": "EmailJob",
      "queue_name": "default",
      "retry_count": 0,
      "enqueue_time": 1640995100
    }
  }
}
```

### Server-Sent Events

```javascript
const eventSource = new EventSource('/api/events/stream');

eventSource.onmessage = function(event) {
  const data = JSON.parse(event.data);
  console.log(`${data.type}:`, data.data);
  
  // Update dashboard in real-time
  updateDashboard(data);
};
```

### WebSocket Connection

```javascript
const ws = new WebSocket('ws://localhost:3000/api/events/ws');

ws.onmessage = function(event) {
  const data = JSON.parse(event.data);
  console.log('Real-time event:', data);
};

// Send ping to keep connection alive
setInterval(() => {
  ws.send(JSON.stringify({action: 'ping'}));
}, 30000);
```

## Performance Considerations

### Metrics Storage
- Metrics are stored in Redis with automatic expiration
- Use time-based windows for rate calculations
- Consider implementing metric aggregation for high-volume systems

### Real-time Events
- Event streams are filtered by Redis pattern matching
- Use specific filters to reduce bandwidth: `["mosquito:queue:*"]`
- Implement client-side reconnection logic for production use

### API Pagination
- Large job lists are paginated (default 50 items per page)
- Use `page` and `per_page` parameters for navigation
- Monitor API response times with large datasets

## Examples

See the `demo/` directory for complete examples:

- `demo/dashboard_api_example.cr` - Basic API usage demonstration
- `demo/web_server_example.cr` - Complete HTTP server with HTML dashboard

## Integration with Web Frameworks

The API integrates easily with Crystal web frameworks:

### Kemal Example

```crystal
require "kemal"
require "mosquito"

# Configure Mosquito
Mosquito.configure do |settings|
  settings.publish_metrics = true
end

# Dashboard routes
get "/api/dashboard" do |env|
  env.response.content_type = "application/json"
  data = Mosquito::Api::WebInterface.dashboard_overview
  Mosquito::Api::WebInterface.json_response(data)
end

get "/api/queues" do |env|
  env.response.content_type = "application/json"
  data = Mosquito::Api::WebInterface.queues_index
  Mosquito::Api::WebInterface.json_response(data)
end

# Real-time events
get "/api/events/stream" do |env|
  env.response.content_type = "text/event-stream"
  Mosquito::Api::Realtime::SSEHandler.handle(env.response)
end

Kemal.run
```

### Lucky Example

```crystal
# In src/actions/api/dashboard_action.cr
class Api::DashboardAction < ApiAction
  get "/api/dashboard" do
    data = Mosquito::Api::WebInterface.dashboard_overview
    json Mosquito::Api::WebInterface.json_response(data)
  end
end

# In src/actions/api/events_action.cr  
class Api::EventsAction < ApiAction
  get "/api/events/stream" do
    response.content_type = "text/event-stream"
    Mosquito::Api::Realtime::SSEHandler.handle(response)
  end
end
```

This comprehensive API enables building sophisticated monitoring and management interfaces for Mosquito job queues, providing the same level of insight and control as Sidekiq's web interface.