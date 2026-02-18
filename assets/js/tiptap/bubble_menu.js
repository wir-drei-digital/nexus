import { Plugin, PluginKey } from "@tiptap/pm/state"
import { Extension } from "@tiptap/core"
import tippy from "tippy.js"

const pluginKey = new PluginKey("bubbleMenu")

const LINK_SVG = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
  <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/>
  <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>
</svg>`

function createMenuElement(editor) {
  const menu = document.createElement("div")
  menu.className = "bubble-menu"

  const buttons = [
    { label: "B", mark: "bold", style: "font-weight:700" },
    { label: "I", mark: "italic", style: "font-style:italic" },
    { label: "U", mark: "underline", style: "text-decoration:underline" },
    { label: "S", mark: "strike", style: "text-decoration:line-through" },
    {
      label: "</>",
      mark: "code",
      style: "font-family:monospace;font-size:0.75rem",
    },
  ]

  buttons.forEach(({ label, mark, style }) => {
    const btn = document.createElement("button")
    btn.innerHTML = `<span style="${style}">${label}</span>`
    btn.setAttribute("data-mark", mark)
    btn.addEventListener("mousedown", (e) => {
      e.preventDefault()
      editor.chain().focus().toggleMark(mark).run()
    })
    menu.appendChild(btn)
  })

  // Separator
  const sep = document.createElement("div")
  sep.className = "bubble-menu-separator"
  menu.appendChild(sep)

  // Link button
  const linkBtn = document.createElement("button")
  linkBtn.innerHTML = LINK_SVG
  linkBtn.setAttribute("data-action", "link")
  linkBtn.addEventListener("mousedown", (e) => {
    e.preventDefault()
    if (editor.isActive("link")) {
      editor.chain().focus().unsetLink().run()
      updateActiveStates(menu, editor)
      return
    }
    toggleLinkInput(menu, editor)
  })
  menu.appendChild(linkBtn)

  // Link input row (hidden by default)
  const linkRow = document.createElement("div")
  linkRow.className = "bubble-menu-link-input"
  linkRow.style.display = "none"

  const urlInput = document.createElement("input")
  urlInput.type = "text"
  urlInput.className = "bubble-menu-url-input"
  urlInput.placeholder = "Paste URL..."

  urlInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") {
      e.preventDefault()
      const url = urlInput.value.trim()
      if (url && !/^(javascript|data|vbscript):/i.test(url)) {
        editor.chain().focus().setLink({ href: url }).run()
      }
      hideLinkInput(menu)
    }
    if (e.key === "Escape") {
      e.preventDefault()
      hideLinkInput(menu)
      editor.commands.focus()
    }
  })

  linkRow.appendChild(urlInput)
  menu.appendChild(linkRow)

  return menu
}

function toggleLinkInput(menu, editor) {
  const linkRow = menu.querySelector(".bubble-menu-link-input")
  const urlInput = menu.querySelector(".bubble-menu-url-input")
  if (!linkRow || !urlInput) return

  const isVisible = linkRow.style.display !== "none"
  if (isVisible) {
    hideLinkInput(menu)
    return
  }

  // Pre-fill with existing href if editing a link
  const attrs = editor.getAttributes("link")
  urlInput.value = attrs.href || ""

  linkRow.style.display = "flex"
  // Small delay to let the menu reposition
  setTimeout(() => urlInput.focus(), 50)
}

function hideLinkInput(menu) {
  const linkRow = menu.querySelector(".bubble-menu-link-input")
  if (linkRow) linkRow.style.display = "none"
}

function updateActiveStates(menu, editor) {
  menu.querySelectorAll("button[data-mark]").forEach((btn) => {
    const mark = btn.getAttribute("data-mark")
    btn.classList.toggle("is-active", editor.isActive(mark))
  })
  const linkBtn = menu.querySelector('button[data-action="link"]')
  if (linkBtn) {
    linkBtn.classList.toggle("is-active", editor.isActive("link"))
  }
}

export const BubbleMenu = Extension.create({
  name: "customBubbleMenu",

  addProseMirrorPlugins() {
    const editor = this.editor
    let popup = null
    let menuEl = null

    return [
      new Plugin({
        key: pluginKey,
        view: () => {
          menuEl = createMenuElement(editor)

          popup = tippy("body", {
            getReferenceClientRect: null,
            appendTo: () => document.body,
            content: menuEl,
            interactive: true,
            trigger: "manual",
            placement: "top",
            offset: [0, 8],
          })

          return {
            update: (view, prevState) => {
              const { state } = view
              const { selection } = state
              const { empty, from, to } = selection

              // Don't hide while user is typing in the link URL input
              const linkRow = menuEl.querySelector(".bubble-menu-link-input")
              if (linkRow && linkRow.style.display !== "none") return

              if (empty || !view.hasFocus()) {
                popup?.[0]?.hide()
                hideLinkInput(menuEl)
                return
              }

              // Don't show for node selections (images, etc)
              if (selection.node) {
                popup?.[0]?.hide()
                hideLinkInput(menuEl)
                return
              }

              // Don't show inside code blocks
              const $from = state.doc.resolve(from)
              if ($from.parent.type.name === "codeBlock") {
                popup?.[0]?.hide()
                hideLinkInput(menuEl)
                return
              }

              updateActiveStates(menuEl, editor)

              popup?.[0]?.setProps({
                getReferenceClientRect: () => {
                  const coords = view.coordsAtPos(from)
                  const endCoords = view.coordsAtPos(to)
                  return {
                    top: coords.top,
                    bottom: endCoords.bottom,
                    left: coords.left,
                    right: endCoords.right,
                    width: endCoords.right - coords.left,
                    height: endCoords.bottom - coords.top,
                    x: coords.left,
                    y: coords.top,
                  }
                },
              })
              popup?.[0]?.show()
            },

            destroy: () => {
              popup?.[0]?.destroy()
              menuEl?.remove()
            },
          }
        },
      }),
    ]
  },
})
