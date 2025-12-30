# lib/agent_web_web/components/messages.ex
defmodule AgentWebWeb.MessagesComponent do
  use AgentWebWeb, :html

  # Import Earmark for markdown rendering
  # import Earmark, only: [as_html!: 1]

  attr :messages, :list, default: []
  attr :streaming, :boolean, default: false
  attr :stream_buffer, :string, default: ""
  attr :conversation_id, :string, default: nil

  def messages(assigns) do
    ~H"""
    <div class="flex-1 overflow-y-auto max-h-[calc(100vh-320px)]">
      <div class="p-5 space-y-6">
        <%= for m <- @messages do %>
          <div id={"message-#{m["id"] || :rand.uniform(10000)}"} class={bubble_class(m["role"])}>
            <!-- Message Header -->
            <div class="flex items-center justify-between mb-3">
              <div class="flex items-center gap-3">
                <div class={role_avatar_class(m["role"])}>
                  <span class="text-base-100">
                    <%= role_avatar_icon(m["role"]) %>
                  </span>
                </div>
                <div>
                  <span class="text-sm font-semibold capitalize">
                    <%= role_display_name(m["role"]) %>
                  </span>
                  <div class="text-xs text-base-content/70 flex items-center gap-2">
                    <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                    <span>
                      <%= m["timestamp"] || "Just now" %>
                    </span>
                  </div>
                </div>
              </div>

              <!-- Message Actions -->
              <div class="flex gap-1 opacity-0 hover:opacity-100 transition-opacity">
                <button
                  class="btn btn-xs btn-ghost btn-circle"
                  phx-click="copy_message"
                  phx-value-content={m["content"]}
                  title="Copy to clipboard"
                >
                  <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                  </svg>
                </button>
              </div>
            </div>

            <!-- Message Content with Markdown -->
            <div class="message-content">
              <%= if should_render_as_markdown?(m["content"]) do %>
                <!-- Rendered Markdown -->
                <div class="prose prose-lg max-w-none dark:prose-invert prose-headings:font-semibold prose-p:my-3 prose-ul:my-3 prose-ol:my-3 prose-li:my-1 prose-blockquote:border-l-4 prose-blockquote:border-primary prose-blockquote:pl-4 prose-blockquote:italic prose-blockquote:my-4 prose-pre:bg-base-300 prose-pre:p-4 prose-pre:rounded-box prose-pre:overflow-x-auto prose-code:before:content-none prose-code:after:content-none prose-code:bg-base-300 prose-code:px-1 prose-code:py-0.5 prose-code:rounded prose-code:text-sm prose-code:font-mono prose-table:my-4 prose-th:bg-base-200 prose-th:font-semibold prose-a:text-primary prose-a:no-underline hover:prose-a:text-primary-focus prose-strong:font-semibold">
                  <%= raw(render_markdown(m["content"])) %>
                </div>
              <% else %>
                <!-- Plain Text -->
                <div class="whitespace-pre-wrap text-base-content font-sans leading-relaxed">
                  <%= m["content"] %>
                </div>
              <% end %>
            </div>

            <!-- Optional: Token Count -->
            <%= if m["token_count"] do %>
              <div class="mt-2 text-xs text-base-content/50 flex justify-end">
                <span class="badge badge-sm badge-outline">
                  <%= m["token_count"] %> tokens
                </span>
              </div>
            <% end %>
          </div>
        <% end %>

        <!-- Streaming Message -->
        <%= if @streaming do %>
          <div class="chat chat-start">
            <div class="chat-image avatar">
              <div class="w-10 rounded-full bg-gradient-to-r from-primary to-secondary flex items-center justify-center">
                <svg class="w-5 h-5 text-base-100" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
                </svg>
              </div>
            </div>

            <div class="chat-header mb-2">
              <span class="font-semibold">Assistant</span>
              <time class="text-xs opacity-50 ml-2">Streaming...</time>
            </div>

            <div class="chat-bubble chat-bubble-primary">
              <!-- Streaming content with markdown -->
              <div class="prose prose-sm max-w-none dark:prose-invert prose-pre:bg-base-300/50 prose-code:bg-base-300/50">
                <%= raw(render_markdown(@stream_buffer)) %>
              </div>

              <!-- Typing indicator -->
              <div class="flex space-x-1 mt-3">
                <div class="w-2 h-2 bg-primary-content rounded-full animate-bounce"></div>
                <div class="w-2 h-2 bg-primary-content rounded-full animate-bounce" style="animation-delay: 0.2s"></div>
                <div class="w-2 h-2 bg-primary-content rounded-full animate-bounce" style="animation-delay: 0.4s"></div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper Functions

  defp bubble_class("user"), do: "bg-base-200 border border-base-300 rounded-box p-5"
  defp bubble_class("assistant"), do: "bg-gradient-to-br from-primary/10 to-secondary/10 border border-primary/20 rounded-box p-5"
  defp bubble_class(_), do: "bg-base-100 border border-base-300 rounded-box p-5"

  defp role_avatar_class("user"),
    do: "w-10 h-10 rounded-full bg-gradient-to-r from-accent to-accent-focus flex items-center justify-center text-base-100"
  defp role_avatar_class("assistant"),
    do: "w-10 h-10 rounded-full bg-gradient-to-r from-primary to-secondary flex items-center justify-center text-base-100"
  defp role_avatar_class(_),
    do: "w-10 h-10 rounded-full bg-base-300 flex items-center justify-center text-base-content"

  # Fixed: Return plain HTML strings instead of ~H sigils
  defp role_avatar_icon("user") do
    """
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
    </svg>
    """
  end

  defp role_avatar_icon("assistant") do
    """
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
    </svg>
    """
  end

  defp role_avatar_icon(_), do: "?"

  defp role_display_name("user"), do: "You"
  defp role_display_name("assistant"), do: "Assistant"
  defp role_display_name(role), do: String.capitalize(role)

  defp should_render_as_markdown?(content) when is_binary(content) do
    # Check if content contains markdown patterns
    String.contains?(content, [
      "# ",
      "## ",
      "### ",
      "#### ",
      "##### ",
      "###### ",  # Headers
      "```",      # Code blocks
      "`",        # Inline code
      "**",       # Bold
      "* ",       # List items or italics
      "- ",       # List items
      "+ ",       # List items
      "> ",       # Blockquotes
      "|",        # Tables
      "[",        # Links
      "!",        # Images
      "~~"        # Strikethrough
    ])
  end

  defp should_render_as_markdown?(_), do: false

  defp render_markdown(content) when is_binary(content) do
    # Basic sanitization and markdown rendering
    options = [
      gfm: true,                    # GitHub Flavored Markdown
      breaks: true,                 # Convert line breaks to <br>
      smartypants: true,            # Smart quotes, dashes, etc.
      code_class_prefix: "language-"
    ]

    case Earmark.as_html(content, options) do
      {:ok, html, _} ->
        # Post-process HTML for better styling
        html
        |> String.replace(~r/<pre><code class="language-(\w+)">/,
          ~s(<div class="mockup-code"><pre><code class="language-\\1">))
        |> String.replace(~r/<\/code><\/pre>/, ~s(</code></pre></div>))
        |> String.replace(~r/<code>/, ~s(<code class="bg-base-300 px-1 py-0.5 rounded text-sm font-mono">))

      {:error, _, _} ->
        # Fallback to plain text with HTML escaping
        Phoenix.HTML.html_escape(content)
    end
  end

  defp render_markdown(_), do: ""
end
