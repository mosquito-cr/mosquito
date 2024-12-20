"use strict";

import BaseComponent from '../../lib/base-component.js'

const html = await BaseComponent.fetchHTML('/javascript/components/queue/queue.html')
const css = await BaseComponent.fetchCSS('/javascript/components/queue/queue.css')

export default class Queue extends BaseComponent {
  constructor () {
    super()

    this.html = html
    this.css = css

    this.attachHTML()
    this.attachCSS()

    this.depth = 0
    this.nameTag = this.shadowRoot.getElementById('name')
    this.depthTag = this.shadowRoot.getElementById('depth')
  }

  connectedCallback() {
    this.nameTag.textContent = this.dataset.queueName
  }

  broadcastMessageReceived(message) {
    switch (message.title) {
      case "enqueue-job":
      case "dequeue":
        this.depth = message.depth || this.depth
        break
      default:
        console.log(`unknown message ${message.title}`, message)
    }

    this.depthTag.textContent = this.depth
  }

  updateDetails(details) {
    this.depth = details.sizes.waiting
  }
}

customElements.define('mosquito-queue', Queue)
