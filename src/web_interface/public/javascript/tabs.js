"use strict";

class TabManager {
  constructor(tabs, tabContent) {
    this.tabs = tabs.querySelectorAll("a")
    this.tabContent = tabContent
    this._manageHistory = false

    for (let tab of this.tabs) {
      tab.addEventListener("click", (e) => {
        e.preventDefault()
        if (tab.classList.contains("active")) return
        this.tabClicked(tab)
      })
    }

    window.addEventListener("popstate", this.historyChanged.bind(this))
  }

  get manageHistory() {
    return this._manageHistory;
  }

  set manageHistory(value) {
    this._manageHistory = value;
    if (value) {
      this.historyChanged()
    }
  }

  lookupTabByAnchor(anchor) {
    if (anchor == "") return this.tabs[0]
    for (let tab of this.tabs)
      if (tab.dataset.tabTarget === anchor)
        return tab
  }

  tabClicked(tab) {
    const target = tab.dataset.tabTarget

    for (let tab of this.tabs)
      tab.classList.remove("active")

    for (let pane of this.tabContent.children)
      pane.classList.remove("active")

    tab.classList.add("active")
    this.tabContent.children[target].classList.add("active")

    this.manageHistory && history.pushState(null, null, "#" + target)
  }

  historyChanged() {
    this.tabClicked(this.lookupTabByAnchor(location.hash.substring(1)))
  }
}

export default TabManager
