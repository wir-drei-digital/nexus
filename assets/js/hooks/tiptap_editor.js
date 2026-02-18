import { Editor } from "@tiptap/core"
import StarterKit from "@tiptap/starter-kit"
import Placeholder from "@tiptap/extension-placeholder"
import Image from "@tiptap/extension-image"
import Link from "@tiptap/extension-link"
import Underline from "@tiptap/extension-underline"
import CodeBlockLowlight from "@tiptap/extension-code-block-lowlight"
import Typography from "@tiptap/extension-typography"
import { common, createLowlight } from "lowlight"
import { SlashCommand } from "../tiptap/slash_command"
import { BubbleMenu } from "../tiptap/bubble_menu"
import { DragHandle } from "../tiptap/drag_handle"

const lowlight = createLowlight(common)

const TiptapEditor = {
  mounted() {
    const editorEl = this.el.querySelector("[data-tiptap-editor]")
    if (!editorEl) return

    // Read section key — identifies which template section this editor controls
    this._sectionKey = this.el.dataset.sectionKey || "body"

    let initialContent = { type: "doc", content: [{ type: "paragraph" }] }
    try {
      const raw = this.el.dataset.content
      if (raw) initialContent = JSON.parse(raw)
    } catch (_) {}

    this._pendingUpdate = false
    this._debounceTimer = null
    this._autoSaveTimer = null

    this.editor = new Editor({
      element: editorEl,
      extensions: [
        StarterKit.configure({
          codeBlock: false,
        }),
        Placeholder.configure({
          placeholder: "Type '/' for commands...",
        }),
        Image.configure({
          inline: false,
          allowBase64: false,
        }),
        Link.configure({
          openOnClick: false,
          autolink: true,
        }),
        Underline,
        CodeBlockLowlight.configure({
          lowlight,
        }),
        Typography,
        SlashCommand,
        BubbleMenu,
        DragHandle,
      ],
      content: initialContent,
      onUpdate: ({ editor }) => {
        if (this._pendingUpdate) {
          this._pendingUpdate = false
          return
        }

        // Instant unsaved feedback
        this.pushEvent("mark_unsaved", {})

        // 1s debounce: sync content to LiveView assigns
        clearTimeout(this._debounceTimer)
        this._debounceTimer = setTimeout(() => {
          this.pushEvent("section_content_changed", {
            key: this._sectionKey,
            content: editor.getJSON(),
          })
        }, 1000)

        // 3s debounce: trigger auto-save to DB
        clearTimeout(this._autoSaveTimer)
        this._autoSaveTimer = setTimeout(() => {
          // Clear the content sync timer since auto_save includes content
          clearTimeout(this._debounceTimer)
          this.pushEvent("auto_save", {
            key: this._sectionKey,
            content: editor.getJSON(),
          })
        }, 3000)
      },
    })

    // Listen for section-specific content updates (e.g., locale switching)
    this.handleEvent(`set_section_content_${this._sectionKey}`, ({ content }) => {
      clearTimeout(this._debounceTimer)
      clearTimeout(this._autoSaveTimer)
      this._pendingUpdate = true
      this.editor.commands.setContent(content)
    })

    // Also listen for the generic event (backwards compat)
    this.handleEvent("set_editor_content", ({ content }) => {
      clearTimeout(this._debounceTimer)
      clearTimeout(this._autoSaveTimer)
      this._pendingUpdate = true
      this.editor.commands.setContent(content)
    })
  },

  destroyed() {
    clearTimeout(this._debounceTimer)
    clearTimeout(this._autoSaveTimer)
    if (this.editor) {
      this.editor.destroy()
      this.editor = null
    }
  },
}

export default TiptapEditor
