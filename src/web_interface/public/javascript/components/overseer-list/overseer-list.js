"use strict";

import BaseComponent from '../../lib/base-component.js'
import Builder from "../../lib/builder.js"

const html = await BaseComponent.fetchHTML('/javascript/components/overseer-list/overseer-list.html')
const css = await BaseComponent.fetchCSS('/javascript/components/overseer-list/overseer-list.css')

export default class OverseerList extends BaseComponent {
  constructor () {
    super()

    this.html = html
    this.css = css

    this.childNest = []

    this.attachHTML()
    this.attachCSS()

    this.list = this.shadowRoot.querySelector("#overseers")
  }
}

customElements.define('mosquito-overseer-list', OverseerList)
