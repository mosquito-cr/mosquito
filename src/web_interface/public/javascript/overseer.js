"use strict";

import Executor from './executor.js'
import Nest from './nest.js'

export default class Overseer {
  static template = null

  static setTemplate(elem) {
    Overseer.template = elem
  }

  onMessage(channel, message) {
    this.lastMessageReceivedAt = (new Date()).getTime()

    // overseer message
    if (channel.length == 3) {
      this.overseerMessage(message)
      return
    }

    // queuelist message
    else if (channel.length == 4) { }

    // executor message
    else if (channel.length == 5) {
      this.executorNest
        .findOrHatch(channel[4])
        .onMessage(channel, message)

      this.executorMessage(channel[4], message)
      return
    }
  }

  overseerMessage(message) {
    switch(message.event) {
      case "coordinating":
        this.setCoordinatingFlag(true)
        break
      case "stopping-coordinating":
        this.setCoordinatingFlag(false)
        break
      case "executor-died":
        // { event: "executor-died", executor: "b795db84445aae99" }
        const executor = this.executorNest.findAndRemove(message.executor)
        if (executor)
          executor.blinkAndRemove()
        break
      default:
        console.error(`Unknown overseer message`, message)
    }
  }

  constructor(overseerId) {
    this.id = overseerId
    this.element = null
    this.updateTimeout = null
    this.lastActiveAt = null
    this.fetchExecutors()
    this.lastMessageReceivedAt = (new Date()).getTime()

    this.updateSelfTicker = setInterval(this.fetchSelfIfIdle.bind(this), 2000)
  }

  appendTo(element) {
    const template = Overseer.template.content.cloneNode(true)
    template.querySelector(".overseer").dataset.id = this.id
    element.appendChild(template)

    this.element = element.querySelector(`.overseer[data-id="${this.id}"]`)
    this.executorNest = new Nest(this.element.querySelector(".executors tbody"), Executor)
    this.updateSummary()
  }

  updateSummary() {
    const executorCount = this.executorNest.count
    const busyExecutorCount = Object.values(this.executorNest.hatchlings).filter(executor => executor.busy).length

    const summary = this.element.querySelector(".summary")

    if (busyExecutorCount > 0)
      summary.textContent = `${busyExecutorCount}/${executorCount} busy`
    else
      summary.textContent = `idle`

    if (summary.classList.contains('hidden'))
      summary.classList.remove('hidden')

    // const isInactive = this.lastActiveAt < (new Date()).getTime() - 5000
    // this.element.classList.toggle('inactive', isInactive)

    this.element.querySelector('.overseer-id').textContent = `<${this.id.slice(-6)}>`
  }

  executorMessage(executorId, message) {
    switch(message.event) {
      case "starting":
        clearTimeout(this.updateTimeout)
        this.updateSummary()
        break

      case "job-finished":
        clearTimeout(this.updateTimeout)
        this.updateTimeout = setTimeout(() => {
          this.updateSummary()
        }, 80)
        break
    }
  }

  fetchSelfIfIdle() {
    let now = (new Date()).getTime()
    if (this.lastMessageReceivedAt < now - 5000) {
      this.fetchSelf().then(this.updateSummary.bind(this))
      this.lastMessageReceivedAt = now
    }
  }

  async fetchSelf() {
    fetch(`/api/overseers/${this.id}`)
    .then(response => response.json())
    .then((overseer) => {
      this.lastActiveAt = overseer.last_active_at
    }).catch(error => console.error(error))
  }

  async fetchExecutors() {
    fetch(`/api/overseers/${this.id}/executors`)
    .then(response => response.json())
    .then(({executors}) => {
      executors.forEach(executor => {
        this
          .executorNest
          .findOrHatch(executor.id)
          .setState({
            progress: executor.current_job == null ? 0 : 100,
            spin: true,
            job: executor.current_job,
            queue: executor.current_job_queue
          })
      })
      this.updateSummary()
    }).catch(error => console.error(error))
  }
}
