"use strict";

export default class BaseComponent extends HTMLElement {
  static async fetchHTML(path) {
    const html = await fetch(path)
      .then(response => response.text())

    return html
  }

  static async fetchCSS(path) {
    const styles = await fetch(path)
      .then(response => response.text())

    return styles
  }

  constructor() {
    super()

    this.attachShadow({ mode: 'open' })
    this.domAttached = false

    this.html = null
    this.css = null
  }

  async attachCSS() {
    const styleElem = document.createElement('style')
    styleElem.setAttribute('type', 'text/css')
    styleElem.textContent = this.css
    this.shadowRoot.appendChild(styleElem)
  }

  async attachHTML() {
    const parser = new DOMParser()
    const parsedHtml = parser.parseFromString(this.html, 'text/html')

    this.shadowRoot.appendChild(parsedHtml.documentElement)
    this.domAttached = true
    this.dispatchEvent(new CustomEvent('DomAttached'))
    this.readyCallback()
  }

  readyCallback() { }

  waitForReady(fn) {
    if (this.domAttached) {
      fn()
    } else {
      this.addEventListener(
        'DomAttached', () => fn(),
        { once: true, passive: true }
      )
    }
  }

  elem(selector) {
    return this.shadowRoot.querySelector(selector)
  }
}
