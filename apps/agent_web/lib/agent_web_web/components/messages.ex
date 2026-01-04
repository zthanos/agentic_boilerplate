# lib/agent_web_web/components/messages.ex
defmodule AgentWebWeb.MessagesComponent do
  use AgentWebWeb, :html
  import AgentWebWeb.IconsComponent

  attr :messages, :list, default: []
  attr :streaming, :boolean, default: false
  attr :stream_buffer, :string, default: ""
  attr :conversation_id, :string, default: nil

  def messages(assigns) do
    ~H"""
    <div
      class="flex-1 overflow-y-auto max-h-[calc(100vh-320px)] scroll-smooth bg-base-100"
      phx-hook="AutoScroll"
      id="messages-container"
    >
      <div class="divide-y divide-base-300">
        <%= for m <- @messages do %>
          <div
            id={"message-#{m["id"] || :rand.uniform(10000)}"}
            class={["group px-6 py-8 transition-colors", bubble_class(m["role"])]}
          >
            <div class="max-w-4xl mx-auto">
              <div class="flex items-center justify-between mb-4">
                <div class="flex items-center gap-3">
                  <div class={role_avatar_class(m["role"])}>
                    <%= if m["role"] == "user" do %>
                      <.user_icon class="w-4 h-4" />
                    <% else %>
                      <.assistant_icon class="w-4 h-4" />
                    <% end %>
                  </div>

                  <div class="flex items-baseline gap-3">
                    <span class="text-sm font-bold tracking-tight text-base-content capitalize">
                      {role_display_name(m["role"])}
                    </span>
                    <span class="text-[11px] font-medium uppercase tracking-wider text-base-content/40 flex items-center gap-1.5">
                      {m["timestamp"] || "Just now"}
                    </span>
                  </div>
                </div>

                <div class="flex gap-2 opacity-0 group-hover:opacity-100 transition-opacity">
                  <button
                    class="btn btn-xs btn-outline btn-ghost border-base-300 hover:bg-base-300"
                    phx-click="copy_message"
                    phx-value-content={m["content"]}
                    title="Copy to clipboard"
                  >
                    <.copy_icon class="w-3.5 h-3.5 mr-1" />
                    <span class="text-[10px] font-bold uppercase">Copy</span>
                  </button>
                </div>
              </div>

              <div class="pl-11">
                <div class="message-content">
                  <%= if should_render_as_markdown?(m["content"]) do %>
                    <div class="prose prose-sm md:prose-base max-w-none dark:prose-invert
                                prose-headings:font-bold prose-headings:text-base-content
                                prose-p:leading-relaxed prose-pre:bg-base-200 prose-pre:border
                                prose-pre:border-base-300 prose-table:border prose-table:rounded-lg">
                      {raw(render_markdown(m["content"]))}
                    </div>
                  <% else %>
                    <div class="whitespace-pre-wrap text-base-content/90 font-sans leading-relaxed text-sm md:text-base">
                      {m["content"]}
                    </div>
                  <% end %>
                </div>

                <%= if m["token_count"] do %>
                  <div class="mt-4 flex items-center gap-2">
                    <span class="text-[10px] font-mono text-base-content/40 uppercase tracking-widest">
                      Usage: {m["token_count"]} tokens
                    </span>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>

        <%= if @streaming do %>
          <div class="px-6 py-8 bg-primary/5 border-l-4 border-primary">
            <div class="max-w-4xl mx-auto">
              <div class="flex items-center gap-3 mb-4">
                <div class="w-8 h-8 rounded bg-primary flex items-center justify-center text-primary-content">
                  <.assistant_icon class="w-4 h-4" />
                </div>
                <span class="text-sm font-bold text-primary italic animate-pulse">
                  Assistant is responding...
                </span>
              </div>

              <div class="pl-11">
                <!-- Only display response content, no workflow steps -->
                <div class="prose prose-sm max-w-none dark:prose-invert">
                  {raw(render_markdown(@stream_buffer))}
                </div>
                <div class="flex space-x-1.5 mt-4">
                  <div class="w-1.5 h-1.5 bg-primary/40 rounded-full animate-bounce"></div>
                  <div class="w-1.5 h-1.5 bg-primary/40 rounded-full animate-bounce [animation-delay:0.2s]">
                  </div>
                  <div class="w-1.5 h-1.5 bg-primary/40 rounded-full animate-bounce [animation-delay:0.4s]">
                  </div>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper Functions

  # Standard white/dark background
  defp bubble_class("user"), do: "bg-base-100"
  # Subtle tint for assistant
  defp bubble_class("assistant"), do: "bg-base-200/50 border-y border-base-200"
  defp bubble_class(_), do: "bg-base-100"

  defp role_avatar_class("user"),
    do: "w-8 h-8 rounded bg-base-300 flex items-center justify-center text-base-content"

  defp role_avatar_class("assistant"),
    do:
      "w-8 h-8 rounded bg-primary text-primary-content flex items-center justify-center shadow-sm"

  defp role_avatar_class(_),
    do: "w-8 h-8 rounded bg-base-200 flex items-center justify-center text-base-content"

  defp role_display_name("user"), do: "You"
  defp role_display_name("assistant"), do: "Assistant"
  defp role_display_name(role), do: String.capitalize(role)

  defp should_render_as_markdown?(content) when is_binary(content) do
    String.contains?(content, [
      "# ",
      "## ",
      "### ",
      "#### ",
      "##### ",
      "###### ",
      "```",
      "`",
      "**",
      "* ",
      "- ",
      "+ ",
      "> ",
      "|",
      "[",
      "!",
      "~~"
    ])
  end

  defp should_render_as_markdown?(_), do: false

  defp render_markdown(content) when is_binary(content) do
    options = [
      gfm: true,
      breaks: true,
      smartypants: true,
      code_class_prefix: "language-"
    ]

    case Earmark.as_html(content, options) do
      {:ok, html, _} ->
        html
        |> String.replace(
          ~r/<pre><code class="language-(\w+)">/,
          ~s(<div class="mockup-code"><pre><code class="language-\\1">)
        )
        |> String.replace(~r/<\/code><\/pre>/, ~s(</code></pre></div>))
        |> String.replace(
          ~r/<code>/,
          ~s(<code class="bg-base-300 px-1 py-0.5 rounded text-sm font-mono">)
        )

      {:error, _, _} ->
        Phoenix.HTML.html_escape(content)
    end
  end

  defp render_markdown(_), do: ""
end
