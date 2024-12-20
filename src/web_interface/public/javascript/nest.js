"use strict";

export default class Nest {
  constructor(root, hatchable) {
    this.root = root
    this.hatchable = hatchable
    this.hatchlings = {}
    this.count = 0
  }

  findOrHatch(id) {
    let hatchling = this.hatchlings[id]
    if (hatchling)
      return hatchling
    hatchling = this.hatchlings[id] = new this.hatchable(id)
    hatchling.appendTo(this.root)
    this.count ++
    return hatchling
  }

  findAndRemove(id) {
    let hatchling = this.hatchlings[id]
    if (! hatchling) return
    this.count --
    delete this.hatchlings[id]
    return hatchling
  }
}
