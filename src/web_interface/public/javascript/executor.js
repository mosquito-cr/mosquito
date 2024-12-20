"use strict";

export default class Executor {
  static animationFrameLength = 50 // ms
  static template() {
    return document.querySelector("template#executor").content.cloneNode(true)
  }

  static linkTemplate() {
    return document.querySelector("template#executor-link").content.cloneNode(true)
  }

  appendTo(element) {
    const template = Executor.template()
    template.querySelector(".executor-row").dataset.id = this.id
    template.querySelector(".progress-row").dataset.id = this.id

    element.appendChild(template)
    this.detailsRow = element.querySelector(`.executor-row[data-id="${this.id}"]`)
    this.progressRow = element.querySelector(`.progress-row[data-id="${this.id}"]`)

    this.detailsRow.querySelector(".executor-id").textContent = this.id
  }

  blinkAndRemove() {
    this.detailsRow.classList.add("blink")
    setTimeout(this.remove.bind(this), 3000)
  }

  remove() {
    this.detailsRow.remove()
    this.progressRow.remove()
  }

  constructor(executorId) {
    this.id = executorId
    this.timeout = null
  }

  get job() { return this._job }
  set job(value) { this._job = value }

  get queue() { return this._queue }
  set queue(value) { this._queue = value }

  set progress(value) {
    const progressBar = this.progressRow.querySelector('.progress-bar')
    progressBar.style.width = value + '%'
    this.spin = value >= 100
  }

  set spin(value) {
    if (value)
      this.progressRow.querySelector('.progress-bar').classList.add('spin')
    else
      this.progressRow.querySelector('.progress-bar').classList.remove('spin')
  }

  onMessage(channel, message) {
    switch(message.event) {
      case "starting":
        this.busy = true
        this.job = message.job_run
        this.queue = message.from_queue
        this.startWorkAnimation(message)

        break

      case "job-finished":
        this.busy = false
        this.job = null
        this.queue = null
        this.stopWorkAnimation(message)

        break
    }
  }

  clearRefreshTimers() {
    clearTimeout(this.timeout)
    clearInterval(this.timeout)
  }

  updateStatus() {
    if (this.job) {
      const template = Executor.linkTemplate()
      template.querySelector("a").textContent = this.job
      template.querySelector("a").href = `/job_run/${this.job}`
      this.detailsRow.querySelector(".working-on").textContent = ""
      this.detailsRow.querySelector(".working-on").appendChild(template)
    } else   {
      this.detailsRow.querySelector(".working-on").textContent = "idle"
    }
  }

  startWorkAnimation(workDetails) {
    this.clearRefreshTimers()
    this.updateStatus()

    const progressIncrement = 100 / (workDetails.expected_duration_ms / this.constructor.animationFrameLength)

    let progressPercent = 0

    this.timeout = setInterval(() => {
      progressPercent += progressIncrement
      if (progressPercent > 100) progressPercent = 100
      this.progress = progressPercent
    }, this.constructor.animationFrameLength)
  }

  stopWorkAnimation(executorId, workDetails) {
    this.clearRefreshTimers()
    this.progress = 100

    // for a less "blinky" UI, don't make things "idle" until it's been idle for long enough
    // that a new job would be assigned if it existed.
    this.timeout = setTimeout(() => {
      this.progress = 0
      this.updateStatus()
    }, 40)
  }

  setState({spin, progress, job, queue}) {
    this.progress = progress
    this.spin = spin
    this.job = job
    this.queue = queue

    this.busy = job != null
    this.updateStatus()
  }
}
