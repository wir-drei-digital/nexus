// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/nexus"
import topbar from "../vendor/topbar"
import ContentTreeSort from "./hooks/content_tree_sort"
import { createTiptapHook } from "tiptap-phoenix"

// Create base tiptap hook and extend with image insertion + drag-drop upload
const baseTiptapHook = createTiptapHook()

const TiptapEditor = {
  mounted() {
    baseTiptapHook.mounted.call(this)

    const sectionKey = this._sectionKey

    // Listen for image insertion events pushed from the server
    this.handleEvent(`tiptap:insert_image:${sectionKey}`, ({src, alt}) => {
      if (this.editor) {
        this.editor.chain().focus().setImage({src, alt: alt || ""}).run()
      }
    })

    // Set up drag-and-drop image upload on the editor element
    const editorEl = this.el.querySelector("[data-tiptap-editor]")
    if (editorEl) {
      this._handleDragOver = (e) => {
        if (e.dataTransfer && e.dataTransfer.types.includes("Files")) {
          e.preventDefault()
          e.dataTransfer.dropEffect = "copy"
          editorEl.classList.add("ring-2", "ring-primary/50")
        }
      }

      this._handleDragLeave = (_e) => {
        editorEl.classList.remove("ring-2", "ring-primary/50")
      }

      this._handleDrop = (e) => {
        editorEl.classList.remove("ring-2", "ring-primary/50")

        const files = e.dataTransfer && e.dataTransfer.files
        if (!files || files.length === 0) return

        // Only handle image files
        const imageFile = Array.from(files).find(f => f.type.startsWith("image/"))
        if (!imageFile) return

        e.preventDefault()
        e.stopPropagation()

        // Find the hidden upload input and programmatically upload
        const uploadForm = document.getElementById("editor-upload-form")
        if (!uploadForm) return

        const uploadInput = uploadForm.querySelector("input[type='file']")
        if (!uploadInput) return

        // Use the LiveView upload mechanism: create a DataTransfer, set the file,
        // and dispatch an input change event
        const dt = new DataTransfer()
        dt.items.add(imageFile)
        uploadInput.files = dt.files
        uploadInput.dispatchEvent(new Event("input", { bubbles: true }))

        // Store the editor key so the form submission knows which editor to target
        uploadForm.dataset.editorKey = sectionKey

        // Wait for LiveView to process the upload, then submit the form
        // The upload progress needs a moment to register
        setTimeout(() => {
          this.pushEvent("save_editor_upload", { key: sectionKey })
        }, 100)
      }

      editorEl.addEventListener("dragover", this._handleDragOver)
      editorEl.addEventListener("dragleave", this._handleDragLeave)
      editorEl.addEventListener("drop", this._handleDrop)
    }
  },

  destroyed() {
    // Clean up drag-drop listeners
    const editorEl = this.el && this.el.querySelector("[data-tiptap-editor]")
    if (editorEl) {
      if (this._handleDragOver) editorEl.removeEventListener("dragover", this._handleDragOver)
      if (this._handleDragLeave) editorEl.removeEventListener("dragleave", this._handleDragLeave)
      if (this._handleDrop) editorEl.removeEventListener("drop", this._handleDrop)
    }

    baseTiptapHook.destroyed.call(this)
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ContentTreeSort, TiptapEditor},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Handle copy-to-clipboard events from the server
window.addEventListener("phx:copy_to_clipboard", (e) => {
  if (e.detail && e.detail.text) {
    navigator.clipboard.writeText(e.detail.text)
  }
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

