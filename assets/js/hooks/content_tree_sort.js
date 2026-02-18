import Sortable from "../../vendor/sortable"

const ContentTreeSort = {
  mounted() {
    this.sortables = []
    this.initSortables()

    this.handleEvent("tree_updated", ({ success, message }) => {
      if (!success) {
        console.error("Tree update failed:", message)
      }
    })
  },

  updated() {
    this.destroySortables()
    this.initSortables()
  },

  destroyed() {
    this.destroySortables()
  },

  destroySortables() {
    this.sortables.forEach(s => {
      try { s.destroy() } catch (e) {}
    })
    this.sortables = []
  },

  initSortables() {
    const containers = this.el.querySelectorAll(".sortable-container")

    containers.forEach(container => {
      if (container._sortable) return

      const sortable = new Sortable(container, {
        group: "content-tree",
        animation: 150,
        fallbackOnBody: true,
        swapThreshold: 0.65,
        handle: ".drag-handle",
        draggable: ".tree-item",
        ghostClass: "sortable-ghost",

        onEnd: (evt) => {
          const item = evt.item
          const newContainer = evt.to

          this.pushEvent("reorder_tree_item", {
            item_type: item.dataset.type,
            item_id: item.dataset.id,
            new_parent_type: newContainer.dataset.parentType,
            new_parent_id: newContainer.dataset.parentId || null,
            siblings: Array.from(newContainer.children)
              .filter(el => el.classList.contains("tree-item"))
              .map((el, i) => ({ type: el.dataset.type, id: el.dataset.id, position: i }))
          })
        },

        onMove: (evt) => {
          // Prevent directories from being nested inside pages
          if (evt.dragged.dataset.type === "directory" && evt.to.dataset.parentType === "page") {
            return false
          }
          return true
        }
      })

      this.sortables.push(sortable)
    })
  }
}

export default ContentTreeSort
