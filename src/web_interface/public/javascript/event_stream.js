"use strict";

export default class EventStream {
  constructor(path) {
    this.path = path
    this.socket = null
    this.connect()

    this.callbacks = {}
  }

  connect() {
    this.socket = new WebSocket(this.path)
    this.socket.onopen = this.onopen.bind(this)
    this.socket.onmessage = this.onmessage.bind(this)
    this.socket.onerror = this.onerror.bind(this)
    this.socket.onclose = this.onclose.bind(this)

    window.addEventListener("beforeunload", (e) => {
      this.socket.close()
    }, {passive: true})
  }

  onmessage(e) {
    const parsed = JSON.parse(e.data)
    this.dispatchCallbacks("message", parsed)
    this.routeMessage(parsed)
  }

  routeMessage(message) {
    console.log(message)
    switch (message.type) {
      case "broadcast":
        this.dispatchCallbacks("broadcast", message)
        break
    }
  }

  onerror(e) {
    console.log("event stream error")
    console.dir(e)
  }

  onopen(e) {
    this.dispatchCallbacks("ready", null)
  }

  onclose(e) { }

  on(response, callback) {
    if (undefined === this.callbacks[response]) {
      this.callbacks[response] = []
    }

    this.callbacks[response].push(callback)
  }

  dispatchCallbacks(eventName, payload) {
    if (! this.callbacks[eventName]) return
    this.callbacks[eventName].forEach(callback => callback(payload))
  }

  listQueues() { this.socket.send("list-queues") }
  listOverseers() { this.socket.send("list-overseers") }
  queueDetail(name) { this.socket.send(`queue(${name})`) }
}
