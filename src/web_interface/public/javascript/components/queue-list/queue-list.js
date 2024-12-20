"use strict";

import BaseComponent from '../../lib/base-component.js'
import Builder from "../../lib/builder.js"

const html = await BaseComponent.fetchHTML('/javascript/components/queue-list/queue-list.html')
const css = await BaseComponent.fetchCSS('/javascript/components/queue-list/queue-list.css')

export default class QueueList extends BaseComponent {
  constructor () {
    super()

    this.html = html
    this.css = css

    this.attachHTML()
    this.attachCSS()

    this.list = this.shadowRoot.querySelector("#queues")
    this.childNest = []
  }

  connectedCallback() { }

  update(queues) {
    queues.forEach(queue_name => this.fetchChild(queue_name))
  }

  fetchChild(name) {
    const child = this.childNest.find(child => child.dataset.queueName === name)
    if (child) return child
    const tag = Builder.tag('mosquito-queue', {dataset: {queueName: name}})
    this.childNest.push(tag)
    this.list.appendChild(tag)

    return tag
  }

  dispatchMessage(queueName, message) {
    const child = this.fetchChild(queueName)
    child.broadcastMessageReceived(message)
  }

  updateDetails(queueName, details) {
    const child = this.fetchChild(queueName)
    child.updateDetails(details)
  }
}

customElements.define('mosquito-queue-list', QueueList)
