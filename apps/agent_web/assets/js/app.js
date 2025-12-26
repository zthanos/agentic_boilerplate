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
import {hooks as colocatedHooks} from "phoenix-colocated/agent_web"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const Hooks = {
  ...colocatedHooks,
}

Hooks.LlmSSE = {
  mounted() {
    this.abortController = null
    this.reader = null
    this.decoder = new TextDecoder()
    this.buffer = ""
    this.doneReceived = false

    this.handleEvent("sse_start", async ({ url, payload }) => {
      // cancel any previous stream
      try {
        if (this.abortController) this.abortController.abort()
      } catch (_) {}

      this.abortController = new AbortController()
      this.buffer = ""
      this.doneReceived = false

      try {
        const res = await fetch(url, {
          method: "POST",
          headers: {
            "content-type": "application/json",
            "accept": "text/event-stream",
          },
          body: JSON.stringify(payload || {}),
          signal: this.abortController.signal,
        })

        if (!res.ok) {
          const text = await res.text()
          this.pushEvent("sse_error", { error: { message: "http_error", status: res.status, body: text } })
          return
        }

        if (!res.body) {
          this.pushEvent("sse_error", { error: { message: "no_response_body" } })
          return
        }

        this.reader = res.body.getReader()

        while (true) {
          const { value, done } = await this.reader.read()
          if (done) break

          this.buffer += this.decoder.decode(value, { stream: true })
          this._drainFrames()
          if (this.doneReceived) return
        }

        // Stream ended. If we didn't receive "done", treat it as disconnect/error
        if (!this.doneReceived) {
          this.pushEvent("sse_error", { error: { message: "stream_closed_before_done" } })
        }
      } catch (err) {
        // If abort, ignore
        if (err && err.name === "AbortError") return
        this.pushEvent("sse_error", { error: { message: "fetch_stream_error", detail: String(err) } })
      }
    })
  },

  destroyed() {
    try {
      if (this.abortController) this.abortController.abort()
    } catch (_) {}
    this.abortController = null
    this.reader = null
  },

  _drainFrames() {
    // SSE frames are separated by \n\n
    const parts = this.buffer.split("\n\n")
    this.buffer = parts.pop() || ""

    for (const frame of parts) {
      const parsed = this._parseSseFrame(frame)
      if (!parsed) continue

      if (parsed.event === "token") {
        try {
          const data = JSON.parse(parsed.data || "{}")
          this.pushEvent("sse_token", { token: data.token || "" })
        } catch (err) {
          this.pushEvent("sse_error", { error: { message: "token_parse_failed", detail: String(err) } })
        }
      } else if (parsed.event === "done") {
        try {
          const data = JSON.parse(parsed.data || "{}")
          this.doneReceived = true
          this.pushEvent("sse_done", data)
        } catch (err) {
          this.pushEvent("sse_error", { error: { message: "done_parse_failed", detail: String(err) } })
        }
      } else if (parsed.event === "error") {
        try {
          const data = JSON.parse(parsed.data || "{}")
          this.doneReceived = true
          this.pushEvent("sse_error", { error: data.error || data })
        } catch (err) {
          this.pushEvent("sse_error", { error: { message: "server_error_frame_parse_failed", detail: String(err) } })
        }
      }
    }
  },

  _parseSseFrame(frame) {
    // frame like:
    // event: token
    // data: {...}
    const lines = frame.split("\n")
    let event = null
    let data = ""

    for (const line of lines) {
      if (line.startsWith("event:")) {
        event = line.slice("event:".length).trim()
      } else if (line.startsWith("data:")) {
        const chunk = line.slice("data:".length).trim()
        // allow multi-line data, concatenate with \n
        data = data ? data + "\n" + chunk : chunk
      }
    }

    if (!event) return null
    return { event, data }
  }
}



const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})


// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

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
    window.addEventListener("keyup", e => keyDown = null)
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

