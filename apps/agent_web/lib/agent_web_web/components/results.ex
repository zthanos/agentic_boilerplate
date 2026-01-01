# lib/your_app_web/components/results.ex
defmodule AgentWebWeb.ResultsComponent do
  use AgentWebWeb, :html

  attr :result, :map, default: nil
  attr :conversation_id, :string, default: nil

  def results(assigns) do
    ~H"""
    <%= if @result do %>
      <div class="border-t border-base-300">
        <div class="p-5 bg-base-200">
          <h4 class="font-semibold mb-4 flex items-center gap-2">
            <svg
              class="w-5 h-5 text-success"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
            Execution Results
          </h4>
          
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-6">
            <div class="card bg-base-100">
              <div class="card-body p-4">
                <div class="text-xs text-base-content/70 uppercase tracking-wider mb-2">Run ID</div>
                
                <div class="font-mono text-sm break-all flex items-center gap-2">
                  <a
                    class="link link-primary truncate"
                    href={~p"/api/runs/#{@result.run_id}"}
                    target="_blank"
                  >
                    {@result.run_id}
                  </a>
                </div>
              </div>
            </div>
            
            <div class="card bg-base-100">
              <div class="card-body p-4">
                <div class="text-xs text-base-content/70 uppercase tracking-wider mb-2">
                  Conversation ID
                </div>
                
                <a
                  class="font-mono text-sm break-all link link-primary"
                  href={~p"/conversations/#{@conversation_id}"}
                >
                  {@conversation_id}
                </a>
              </div>
            </div>
            
            <div class="card bg-base-100">
              <div class="card-body p-4">
                <div class="text-xs text-base-content/70 uppercase tracking-wider mb-2">Status</div>
                
                <div class="flex items-center gap-2">
                  <span class={status_badge_class(@result.status)}>{@result.status}</span>
                </div>
              </div>
            </div>
            
            <div class="card bg-base-100">
              <div class="card-body p-4">
                <div class="text-xs text-base-content/70 uppercase tracking-wider mb-2">Latency</div>
                
                <div class="flex items-center gap-2">
                  <span class="text-lg font-semibold">{@result.latency_ms}</span>
                  <span class="text-base-content/70">ms</span>
                </div>
              </div>
            </div>
          </div>
          
          <%= if @result.usage do %>
            <div class="card bg-base-100">
              <div class="card-body">
                <h3 class="card-title text-sm">Usage Details</h3>
                
                <div class="stats stats-vertical lg:stats-horizontal shadow w-full">
                  <div class="stat">
                    <div class="stat-title">Prompt Tokens</div>
                    
                    <div class="stat-value text-primary">
                      {Map.get(@result.usage || %{}, "prompt_tokens") ||
                        Map.get(@result.usage || %{}, :prompt_tokens) || 0}
                    </div>
                  </div>
                  
                  <div class="stat">
                    <div class="stat-title">Completion Tokens</div>
                    
                    <div class="stat-value text-secondary">
                      {Map.get(@result.usage || %{}, "completion_tokens") ||
                        Map.get(@result.usage || %{}, :completion_tokens) || 0}
                    </div>
                  </div>
                  
                  <div class="stat">
                    <div class="stat-title">Total Tokens</div>
                    
                    <div class="stat-value text-success">
                      {Map.get(@result.usage || %{}, "total_tokens") ||
                        Map.get(@result.usage || %{}, :total_tokens) || 0}
                    </div>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    <% end %>
    """
  end

  defp status_badge_class(status) do
    case status do
      "success" -> "badge badge-success"
      "error" -> "badge badge-error"
      "pending" -> "badge badge-warning"
      _ -> "badge badge-neutral"
    end
  end
end
