import EventStream from "./event_stream.js"
const eventStream = new EventStream("ws://localhost:3000/events")
eventStream.on("message", message => console.log(message))
