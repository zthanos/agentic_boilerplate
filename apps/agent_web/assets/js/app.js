// apps/agent_web/assets/js/app.js

import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"

// ----------------------------------------------------------------------------
// LiveView Hooks
// ----------------------------------------------------------------------------

const Hooks = {}

Hooks.LlmSSE = {
  mounted() {
    this.reader = null
    this.decoder = new TextDecoder("utf-8")
    this.buffer = ""
    this.doneReceived = false
    this.abortController = null
    this.running = false

    // LiveView tells us to start streaming
    this.handleEvent("sse_start", async ({ url, payload }) => {
      try {
        await this.start(url, payload)
      } catch (err) {
        this.pushEvent("sse_error", {
          error: {
            message: "client_stream_start_failed",
            detail: String(err?.message || err),
          },
        })
      }
    })

    // Optional: allow server/UI to stop
    this.handleEvent("sse_stop", async () => {
      this.stop()
    })
  },

  destroyed() {
    this.stop()
  },

  stop() {
    try {
      if (this.abortController) this.abortController.abort()
    } catch (_) {
      // ignore
    }

    this.abortController = null
    this.reader = null
    this.buffer = ""
    this.doneReceived = false
    this.running = false
  },

  async start(url, payload) {
    // Stop any previous stream
    this.stop()

    this.abortController = new AbortController()
    this.running = true

    const resp = await fetch(url, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        accept: "text/event-stream",
      },
      body: JSON.stringify(payload),
      signal: this.abortController.signal,
    })

    if (!resp.ok) {
      const text = await resp.text().catch(() => "")
      this.running = false

      this.pushEvent("sse_error", {
        error: {
          message: "http_error",
          detail: `HTTP ${resp.status} ${resp.statusText} ${text}`.trim(),
        },
      })
      return
    }

    if (!resp.body) {
      this.running = false
      this.pushEvent("sse_error", {
        error: { message: "no_response_body", detail: "Response has no readable body." },
      })
      return
    }

    this.reader = resp.body.getReader()

    // Main streaming loop
    while (true) {
      const { value, done } = await this.reader.read()

      if (done) break
      if (!value) continue

      // Decode ONCE, normalize CRLF on the chunk, then append
      const chunk = this.decoder.decode(value, { stream: true })
      this.buffer += chunk.replace(/\r\n/g, "\n")

      this._drainFrames()

      // If server sent done event, we can stop reading early
      if (this.doneReceived) break
    }

    // Flush decoder tail (rare but correct)
    try {
      const tail = this.decoder.decode()
      if (tail) {
        this.buffer += tail.replace(/\r\n/g, "\n")
        this._drainFrames()
      }
    } catch (_) {
      // ignore
    }

    this.running = false
  },

  _drainFrames() {
    // SSE events are separated by a blank line
    const parts = this.buffer.split(/\n\n/)
    this.buffer = parts.pop() || ""

    for (const frame of parts) {
      const evt = this._parseFrame(frame)
      if (!evt) continue

      if (evt.type === "token") {
        this.pushEvent("sse_token", { token: evt.token })
      } else if (evt.type === "done") {
        this.doneReceived = true
        const meta = evt.meta && Object.keys(evt.meta).length > 0 ? evt.meta : { done: true }
        this.pushEvent("sse_done", meta)
      } else if (evt.type === "error") {
        this.doneReceived = true
        this.pushEvent("sse_error", { error: evt.error || { message: "unknown_error" } })
      }
    }
  },

  _parseFrame(frame) {
    // frame is multiple lines: "event: x\n" and/or "data: y\n"
    // We support:
    // - event: token, data: {"token":"..."}
    // - event: done,  data: {"meta":{...}}
    // - event: error, data: {"error":{...}}
    //
    // Also support "data: [DONE]" style (OpenAI-ish) defensively.

    const lines = frame.split("\n").filter((l) => l.trim() !== "")
    if (lines.length === 0) return null

    let eventName = null
    const dataLines = []

    for (const line of lines) {
      if (line.startsWith("event:")) {
        eventName = line.slice("event:".length).trim()
      } else if (line.startsWith("data:")) {
        dataLines.push(line.slice("data:".length).trim())
      }
    }

    const dataStr = dataLines.join("\n").trim()

    // OpenAI-ish done marker
    if (dataStr === "[DONE]") {
      return { type: "done", meta: {} }
    }

    // If no explicit event, try to infer from JSON shape
    if (!eventName) {
      const maybe = this._safeJson(dataStr)
      if (maybe?.token != null) return { type: "token", token: String(maybe.token) }
      if (maybe?.meta != null) return { type: "done", meta: maybe.meta }
      if (maybe?.error != null) return { type: "error", error: maybe.error }
      return null
    }

    if (eventName === "token") {
      const obj = this._safeJson(dataStr)
      if (!obj || obj.token == null) return null
      return { type: "token", token: String(obj.token) }
    }

    if (eventName === "done") {
      const obj = this._safeJson(dataStr)
      return { type: "done", meta: obj?.meta || {} }
    }

    if (eventName === "error") {
      const obj = this._safeJson(dataStr)
      return { type: "error", error: obj?.error || { message: "unknown_error" } }
    }

    return null
  },

  _safeJson(s) {
    if (!s) return null
    try {
      return JSON.parse(s)
    } catch (_) {
      return null
    }
  },
}

// ----------------------------------------------------------------------------
// LiveSocket setup
// ----------------------------------------------------------------------------

let csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")

let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", () => topbar.show(300))
window.addEventListener("phx:page-loading-stop", () => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
window.liveSocket = liveSocket
