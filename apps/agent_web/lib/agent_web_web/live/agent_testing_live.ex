defmodule AgentWebWeb.AgentTestingLive do
  use AgentWebWeb, :live_view
  import AgentWebWeb.MessagesComponent
  alias AgentWebWeb.AdminLayouts
  alias AgentRuntime.Llm.Agent.Store, as: AgentStoreDI
  alias AgentWeb.AgentSeeder
  alias AgentWeb.ErrorHandler

  require Logger
  require AgentWebWeb.IconsComponent

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      # ✅ Admin layout assigns
      |> assign(:current_page, :agent_testing)
      |> assign(:current_section, :operations)
      |> assign(:sidebar_collapsed, false)
      |> assign(:page_title, "RAG History Chat")
      |> assign(:loading, false)
      |> assign(:error, nil)
      # Agent testing specific assigns
      |> assign(:selected_agent_id, nil)
      |> assign(:available_agents, [])
      |> assign(:workflow_graph, nil)
      |> assign(:workflow_execution_state, %{})
      |> assign(:chat_messages, [])
      |> assign(:execution_status, %{
        status: :idle,
        started_at: nil,
        completed_at: nil,
        total_steps: 0,
        completed_steps: 0,
        current_step_name: nil
      })
      |> assign(:sse_connection_id, nil)
      |> assign(:error_info, nil)
      |> assign(:streaming, false)
      |> assign(:stream_buffer, "")
      |> assign(:validation_results, nil)
      |> assign(:validation_running, false)
      |> assign(:current_step_id, nil)
      |> assign(:execution_id, nil)
      |> load_available_agents()

    {:ok, socket}
  end

  # ✅ Sidebar toggle handlers
  @impl true
  def handle_info({:toggle_sidebar}, socket) do
    new_state = !socket.assigns.sidebar_collapsed
    {:noreply, assign(socket, :sidebar_collapsed, new_state)}
  end

  @impl true
  def handle_event("toggle_sidebar", _params, socket) do
    new_state = !socket.assigns.sidebar_collapsed
    {:noreply, assign(socket, :sidebar_collapsed, new_state)}
  end

  @impl true
  def handle_event("set_sidebar_state", %{"collapsed" => collapsed}, socket) do
    {:noreply, assign(socket, :sidebar_collapsed, collapsed)}
  end

  @impl true
  def handle_event("select_agent", %{"agent_id" => agent_id}, socket) do
    IO.inspect(agent_id, label: "DEBUG: Selecting agent")

    socket =
      socket
      |> assign(:selected_agent_id, agent_id)
      |> assign(:loading, true)
      |> assign(:error_info, nil)
      |> assign(:execution_id, nil)
      |> reset_workflow_state()
      |> load_agent_workflow(agent_id)
      |> update_chat_interface_for_agent(agent_id)

    IO.inspect(socket.assigns.selected_agent_id, label: "DEBUG: Selected agent ID")
    IO.inspect(socket.assigns.workflow_graph, label: "DEBUG: Workflow graph")

    {:noreply, socket}
  end

  @impl true
  def handle_event("seed_agents", _params, socket) do
    socket = assign(socket, :loading, true)

    case AgentSeeder.seed_test_agents() do
      {:ok, _seeded_agents} ->
        socket =
          socket
          |> assign(:loading, false)
          |> assign(:error_info, nil)
          |> load_available_agents()

        {:noreply, socket}

      {:error, reason} ->
        error_info = ErrorHandler.analyze_error(reason, :seeding)

        socket =
          socket
          |> assign(:loading, false)
          |> assign(:error_info, error_info)

        {:noreply, socket}
    end
  end

  # SSE Event Handlers for streaming chat
  @impl true
  def handle_event("sse_token", %{"token" => token}, socket) do
    # Only handle clean LLM response tokens - no workflow progress mixed in
    buf = (socket.assigns.stream_buffer || "") <> (token || "")
    {:noreply, assign(socket, :stream_buffer, buf)}
  end

  @impl true
  def handle_event("sse_done", payload, socket) do
    # Support both shapes like in PlanExecuteLive
    meta =
      case payload do
        %{"meta" => m} when is_map(m) -> m
        m when is_map(m) -> m
        _ -> %{}
      end

    run_id = Map.get(meta, "run_id")
    trace_id = Map.get(meta, "trace_id")

    assistant_text =
      socket.assigns.stream_buffer
      |> to_string()
      |> String.trim()

    # Create assistant message with clean LLM response content only
    # Workflow progress is handled separately and not mixed into message content
    assistant_message =
      create_assistant_message(assistant_text, %{
        run_id: run_id,
        trace_id: trace_id,
        workflow_id: socket.assigns.workflow_graph && socket.assigns.workflow_graph.id,
        execution_time_ms: Map.get(meta, "latency_ms"),
        token_count: get_in(meta, ["usage", "total_tokens"])
      })

    # Extract workflow progress information if available
    workflow_progress = extract_workflow_progress(meta)

    socket =
      socket
      |> update(:chat_messages, &(&1 ++ [assistant_message]))
      |> assign(:streaming, false)
      |> assign(:stream_buffer, "")
      |> update_execution_status(:completed)
      |> maybe_update_workflow_progress(workflow_progress)

    {:noreply, socket}
  end

  @impl true
  def handle_event("sse_clarify", %{"question" => question, "trace_id" => trace_id}, socket) do
    # Add clarification message to chat
    clarification_message = %{
      "id" => generate_message_id(),
      "role" => "system",
      "content" => "❓ Clarification needed: #{question}",
      "timestamp" => format_timestamp(DateTime.utc_now()),
      "trace_id" => trace_id
    }

    socket =
      socket
      |> update(:chat_messages, &(&1 ++ [clarification_message]))
      |> assign(:streaming, false)
      |> assign(:stream_buffer, "")
      |> update_execution_status(:idle)

    {:noreply, socket}
  end

  @impl true
  def handle_event("sse_error", payload, socket) do
    err =
      case payload do
        %{"error" => e} -> e
        other -> other
      end

    # Analyze error using new error handler
    error_info = ErrorHandler.analyze_error(err, :chat)

    # Create a user-friendly error message
    error_content = format_error_message(err)

    error_message = %{
      "id" => generate_message_id(),
      "role" => "system",
      "content" => error_content,
      "timestamp" => format_timestamp(DateTime.utc_now()),
      "error" => true,
      "recoverable" => is_recoverable_error(err)
    }

    # Extract workflow error information if available
    workflow_error = extract_workflow_error(err)

    socket =
      socket
      |> update(:chat_messages, &(&1 ++ [error_message]))
      |> assign(:streaming, false)
      |> assign(:stream_buffer, "")
      |> assign(:error_info, error_info)
      |> update_execution_status(:failed)
      |> maybe_update_workflow_error(workflow_error)

    {:noreply, socket}
  end

  @impl true
  def handle_event("sse_step_execution", payload, socket) do
    step_name = Map.get(payload, "step_name")
    status = Map.get(payload, "status")
    step_id_raw = Map.get(payload, "step_id")
    execution_time_ms = Map.get(payload, "execution_time_ms")
    error = Map.get(payload, "error")
    timestamp = Map.get(payload, "timestamp")

    # Convert step_id to atom if it's a string (JSON serialization converts atoms to strings)
    step_id =
      case step_id_raw do
        step_id when is_binary(step_id) ->
          try do
            String.to_existing_atom(step_id)
          rescue
            # Keep as string if atom doesn't exist
            ArgumentError -> step_id_raw
          end

        # Keep as-is if already an atom or other type
        step_id ->
          step_id
      end

    socket =
      socket
      |> update_workflow_progress(step_name, status, step_id, execution_time_ms, error)
      |> maybe_update_execution_status(status, step_name)

    {:noreply, socket}
  end

  @impl true
  def handle_event("retry_last_message", _params, socket) do
    # Find the last user message and retry it
    case get_last_user_message(socket.assigns.chat_messages) do
      nil ->
        {:noreply, socket}

      last_message ->
        conversation_id = generate_conversation_id(socket.assigns.selected_agent_id)
        context = build_conversation_context(socket.assigns.chat_messages)

        # Clear error state and retry
        socket =
          socket
          |> assign(:error, nil)
          |> assign(:streaming, true)
          |> assign(:stream_buffer, "")
          |> update_execution_status(:running)

        # Send message for retry
        send(self(), {:chat_send_message, last_message, conversation_id, context})

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, :error_info, nil)}
  end

  # Recovery action handlers
  def handle_event("retry_operation", _params, socket) do
    # Retry the last operation based on context
    cond do
      socket.assigns.selected_agent_id && !socket.assigns.workflow_graph ->
        # Retry loading workflow
        socket = load_agent_workflow(socket, socket.assigns.selected_agent_id)
        {:noreply, socket}

      socket.assigns.available_agents == [] ->
        # Retry loading agents
        socket = load_available_agents(socket)
        {:noreply, socket}

      true ->
        # Generic retry - just clear error
        {:noreply, assign(socket, :error_info, nil)}
    end
  end

  def handle_event("retry_seeding", _params, socket) do
    send(self(), {:recovery_action, "seed_agents", %{}})
    {:noreply, socket}
  end

  def handle_event("reload_agent", _params, socket) do
    if socket.assigns.selected_agent_id do
      socket =
        socket
        |> assign(:error_info, nil)
        |> load_agent_workflow(socket.assigns.selected_agent_id)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("back_to_agent_selection", _params, socket) do
    socket =
      socket
      |> assign(:selected_agent_id, nil)
      |> assign(:workflow_graph, nil)
      |> assign(:error_info, nil)
      |> reset_workflow_state()

    {:noreply, socket}
  end

  # Handle workflow validation requests
  @impl true
  def handle_event("run_validation_tests", _params, socket) do
    if socket.assigns.selected_agent_id do
      socket = assign(socket, :validation_running, true)

      # Run validation tests asynchronously
      send(self(), {:run_validation_tests, socket.assigns.selected_agent_id})

      {:noreply, socket}
    else
      error_info = %{
        message: "No agent selected for validation",
        type: :validation_error,
        context: :validation,
        recovery_actions: ["select_agent"]
      }

      {:noreply, assign(socket, :error_info, error_info)}
    end
  end

  @impl true
  def handle_event("clear_validation_results", _params, socket) do
    socket =
      socket
      |> assign(:validation_results, nil)
      |> assign(:validation_running, false)

    {:noreply, socket}
  end

  def handle_event("check_lm_studio_status", _params, socket) do
    # This could trigger a health check or show guidance
    put_flash(
      socket,
      :info,
      "Please ensure LM Studio is running on localhost:1234 with a model loaded."
    )
    |> then(&{:noreply, &1})
  end

  def handle_event("open_lm_studio_guide", _params, socket) do
    # This could open documentation or show setup instructions
    put_flash(
      socket,
      :info,
      "LM Studio Setup: 1) Download from lmstudio.ai 2) Load a model 3) Start the server on port 1234"
    )
    |> then(&{:noreply, &1})
  end

  # Handle recovery actions from ErrorDisplayComponent
  def handle_info({:recovery_action, event, params}, socket) do
    handle_event(event, params, socket)
  end

  def handle_info({:clear_error}, socket) do
    {:noreply, assign(socket, :error_info, nil)}
  end

  # Handle validation test execution
  def handle_info({:run_validation_tests, agent_id}, socket) do
    case AgentWeb.WorkflowValidator.run_validation_tests(agent_id: agent_id) do
      {:ok, results} ->
        socket =
          socket
          |> assign(:validation_results, results)
          |> assign(:validation_running, false)

        {:noreply, socket}

      {:error, reason} ->
        error_info = %{
          message: "Validation tests failed: #{reason}",
          type: :validation_error,
          context: :validation,
          recovery_actions: ["retry_validation", "check_lm_studio_status"]
        }

        socket =
          socket
          |> assign(:validation_running, false)
          |> assign(:error_info, error_info)

        {:noreply, socket}
    end
  end

  # Handle chat message sending with streaming
  @impl true
  def handle_info({:chat_send_message, message, conversation_id, _context}, socket) do
    if String.trim(message) != "" && socket.assigns.selected_agent_id do
      # Prepare payload for agent execution with streaming - simplified like PlanExecuteLive
      input = %{
        "type" => "chat",
        "messages" => [%{"role" => "user", "content" => message}]
      }

      execution_id = generate_execution_id()

      payload = %{
        # Default profile for testing
        "profile_id" => "req_llm",
        "agent_id" => socket.assigns.selected_agent_id,
        "agent_version" => "latest",
        "input" => input,
        "overrides" => %{},
        "conversation_id" => conversation_id,
        "trace_id" => Ecto.UUID.generate()
      }

      # Add user message to chat
      user_message = create_user_message(message, socket.assigns.selected_agent_id)

      socket =
        socket
        |> update(:chat_messages, &(&1 ++ [user_message]))
        # Clear any previous errors
        |> assign(:error_info, nil)
        |> assign(:streaming, true)
        |> assign(:stream_buffer, "")
        |> assign(:execution_id, execution_id)
        |> assign(:workflow_execution_state, %{})
        |> assign(:current_step_id, nil)
        |> update_execution_status(:running)

      # Start SSE streaming
      {:noreply,
       socket
       |> push_event("sse_start", %{
         url: "/api/agents/execute/stream",
         payload: payload
       })}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:sse_update, data}, socket) do
    # Handle workflow progress updates from SSE events
    socket =
      case data do
        %{type: :workflow_step_start, step_id: step_id, step_name: step_name} ->
          socket
          |> update_workflow_node_status(step_id, :running)
          |> update_execution_status(:running, step_name)
          |> broadcast_workflow_update(:step_start, step_id, step_name)

        %{type: :workflow_step_complete, step_id: step_id, execution_time_ms: time} ->
          socket
          |> update_workflow_node_status(step_id, :completed, %{execution_time_ms: time})
          |> increment_completed_steps()
          |> broadcast_workflow_update(:step_complete, step_id, time)

        %{type: :workflow_step_error, step_id: step_id, error: error} ->
          socket
          |> update_workflow_node_status(step_id, :failed, %{error: error})
          |> update_execution_status(:failed)
          |> broadcast_workflow_update(:step_error, step_id, error)

        %{type: :workflow_complete} ->
          socket
          |> update_execution_status(:completed)
          |> broadcast_workflow_update(:workflow_complete, nil, nil)

        _ ->
          socket
      end

    {:noreply, socket}
  end

  # @impl true
  # def render(assigns) do
  #   ~H"""
  #   <div phx-hook="LlmSSE" id="agent-testing-sse">
  #     <Layouts.app flash={@flash}>
  #       <div class="min-h-screen bg-base-100">
  #         <div class="container mx-auto px-4 py-6">
  #           <!-- Header -->
  #           <div class="mb-6">
  #             <h1 class="text-3xl font-bold text-base-content">Agent Testing Interface</h1>

  #             <p class="text-base-content/70 mt-2">
  #               Test and validate agent behavior through interactive workflows and real-time monitoring
  #             </p>
  #           </div>
  #           <!-- Agent Selection Section -->
  #           <div class="mb-6">
  #             <div class="card bg-base-200 shadow-xl">
  #               <div class="card-body">
  #                 <h2 class="card-title">Agent Selection</h2>

  #                 <%= if @available_agents == [] do %>
  #                   <div class="alert alert-info">
  #                     <div>
  #                       <h3 class="font-bold">No agents available</h3>

  #                       <div class="text-sm">
  #                         No agents are currently available for testing. You can seed test agents to get started.
  #                       </div>
  #                     </div>
  #                   </div>

  #                   <div class="card-actions justify-end">
  #                     <button
  #                       class="btn btn-primary"
  #                       phx-click="seed_agents"
  #                       disabled={@loading}
  #                     >
  #                       {if @loading, do: "Seeding...", else: "Seed Test Agents"}
  #                     </button>
  #                   </div>
  #                 <% else %>
  #                   <form phx-change="select_agent">
  #                     <div class="form-control w-full max-w-xs">
  #                       <label class="label">
  #                         <span class="label-text">Select an agent to test:</span>
  #                       </label>
  #                       <select
  #                         class="select select-bordered w-full max-w-xs"
  #                         name="agent_id"
  #                       >
  #                         <option disabled selected={@selected_agent_id == nil}>
  #                           Choose an agent
  #                         </option>

  #                         <%= for agent <- @available_agents do %>
  #                           <option
  #                             value={agent.id}
  #                             selected={@selected_agent_id == agent.id}
  #                           >
  #                             {agent.name || agent.id}
  #                             <%= if Map.get(agent.metadata || %{}, "test_mode") do %>
  #                               (Test Agent)
  #                             <% end %>
  #                           </option>
  #                         <% end %>
  #                       </select>
  #                     </div>
  #                   </form>
  #                 <% end %>

  #                 <%= if @error_info do %>
  #                   <.live_component
  #                     module={AgentWebWeb.ErrorDisplayComponent}
  #                     id="main-error"
  #                     error={@error_info.message}
  #                     error_type={@error_info.type}
  #                     context={@error_info.context}
  #                     recovery_actions={@error_info.recovery_actions}
  #                     dismissible={true}
  #                     class="mt-4"
  #                   />
  #                 <% end %>
  #               </div>
  #             </div>
  #           </div>
  #           <!-- Main Interface Grid -->
  #           <%= if @selected_agent_id do %>
  #             <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
  #               <!-- Workflow Graph Section -->
  #               <div class="card bg-base-200 shadow-xl">
  #                 <div class="card-body">
  #                   <div class="flex items-center justify-between mb-4">
  #                     <h2 class="card-title">Workflow Visualization</h2>
  #                     <!-- Validation Controls -->
  #                     <div class="flex gap-2">
  #                       <button
  #                         class="btn btn-sm btn-outline"
  #                         phx-click="run_validation_tests"
  #                         disabled={@validation_running || @streaming}
  #                       >
  #                         <%= if @validation_running do %>
  #                           <span class="loading loading-spinner loading-xs"></span> Validating...
  #                         <% else %>
  #                           🧪 Run Tests
  #                         <% end %>
  #                       </button>
  #                       <%= if @validation_results do %>
  #                         <button
  #                           class="btn btn-sm btn-ghost"
  #                           phx-click="clear_validation_results"
  #                         >
  #                           Clear Results
  #                         </button>
  #                       <% end %>
  #                     </div>
  #                   </div>

  #                   <%= if @workflow_graph do %>
  #                     <.live_component
  #                       module={AgentWebWeb.WorkflowGraphComponent}
  #                       id="workflow-graph"
  #                       workflow_spec={@workflow_graph}
  #                       execution_state={@workflow_execution_state}
  #                       current_step={@execution_status.current_step_name}
  #                       class="h-96"
  #                     />
  #                   <% else %>
  #                     <div class="alert alert-info">
  #                       <div>
  #                         <div class="text-sm">
  #                           Workflow graph will be loaded when an agent is selected and initialized.
  #                         </div>
  #                       </div>
  #                     </div>
  #                   <% end %>
  #                   <!-- Validation Results Display -->
  #                   <%= if @validation_results do %>
  #                     <div class="mt-4 p-4 bg-base-100 rounded-lg border border-base-300">
  #                       <h3 class="font-semibold mb-2 flex items-center gap-2">
  #                         🧪 Validation Results
  #                         <%= if @validation_results.passed == @validation_results.total_tests do %>
  #                           <span class="badge badge-success">All Passed</span>
  #                         <% else %>
  #                           <span class="badge badge-error">{@validation_results.failed} Failed</span>
  #                         <% end %>
  #                       </h3>

  #                       <div class="text-sm text-base-content/70 mb-3">
  #                         {@validation_results.passed}/{@validation_results.total_tests} tests passed
  #                         in {@validation_results.execution_time_ms}ms
  #                       </div>

  #                       <div class="space-y-2">
  #                         <%= for result <- @validation_results.results do %>
  #                           <div class={[
  #                             "p-3 rounded border-l-4",
  #                             if(result.status == :passed,
  #                               do: "bg-success/10 border-success",
  #                               else: "bg-error/10 border-error"
  #                             )
  #                           ]}>
  #                             <div class="flex items-center gap-2 mb-1">
  #                               <%= if result.status == :passed do %>
  #                                 <span class="text-success">✓</span>
  #                               <% else %>
  #                                 <span class="text-error">✗</span>
  #                               <% end %>
  #                               <span class="font-medium text-sm">{result.test_name}</span>
  #                               <span class="text-xs text-base-content/50">
  #                                 ({result.execution_time_ms}ms)
  #                               </span>
  #                             </div>

  #                             <div class="text-xs text-base-content/70">{result.details}</div>
  #                           </div>
  #                         <% end %>
  #                       </div>
  #                     </div>
  #                   <% end %>
  #                 </div>
  #               </div>
  #               <!-- Chat Interface Section -->
  #               <div class="card bg-base-200 shadow-xl">
  #                 <div class="card-body">
  #                   <div class="flex items-center justify-between mb-4">
  #                     <h2 class="card-title">Chat Interface</h2>

  #                     <%= if @selected_agent_id do %>
  #                       <div class="badge badge-primary badge-outline">
  #                         Agent: {get_selected_agent_name(assigns)}
  #                       </div>
  #                     <% end %>
  #                   </div>
  #                   <!-- Chat Messages Container -->
  #                   <div class="bg-base-100 rounded-lg border border-base-300 h-96 flex flex-col">
  #                     <!-- Messages Display -->
  #                     <div class="flex-1 overflow-y-auto p-4">
  #                       <%= if @chat_messages == [] do %>
  #                         <div class="text-center text-base-content/50 mt-8">
  #                           <div class="text-lg font-semibold mb-2">Start Testing</div>

  #                           <div class="text-sm">
  #                             Send a message to begin testing the selected agent
  #                           </div>
  #                         </div>
  #                       <% else %>
  #                         <.messages
  #                           messages={@chat_messages}
  #                           streaming={@streaming}
  #                           stream_buffer={@stream_buffer}
  #                           conversation_id={generate_conversation_id(@selected_agent_id)}
  #                         />
  #                       <% end %>
  #                     </div>
  #                     <!-- Workflow Progress Indicator -->
  #                     <%= if @execution_status && @execution_status.status != :idle do %>
  #                       <div class="border-t border-base-300 px-4 py-2 bg-base-50">
  #                         <div class="flex items-center justify-between text-sm">
  #                           <div class="flex items-center gap-2">
  #                             <%= case @execution_status.status do %>
  #                               <% :running -> %>
  #                                 <div class="loading loading-spinner loading-xs text-warning"></div>
  #                                 <span class="text-warning font-medium">Executing</span>
  #                               <% :completed -> %>
  #                                 <div class="text-success">✓</div>
  #                                 <span class="text-success font-medium">Completed</span>
  #                               <% :failed -> %>
  #                                 <div class="text-error">✗</div>
  #                                 <span class="text-error font-medium">Failed</span>
  #                               <% _ -> %>
  #                                 <div class="loading loading-spinner loading-xs"></div>
  #                                 <span class="font-medium">Processing</span>
  #                             <% end %>

  #                             <%= if @execution_status.current_step_name do %>
  #                               <span class="text-base-content/70">
  #                                 : {@execution_status.current_step_name}
  #                               </span>
  #                             <% end %>
  #                           </div>

  #                           <div class="text-base-content/70">
  #                             {@execution_status.completed_steps}/{@execution_status.total_steps} steps
  #                           </div>
  #                         </div>
  #                         <!-- Progress bar -->
  #                         <%= if @execution_status.total_steps > 0 do %>
  #                           <div class="mt-2">
  #                             <div class="w-full bg-base-300 rounded-full h-1.5">
  #                               <div
  #                                 class={[
  #                                   "h-1.5 rounded-full transition-all duration-300",
  #                                   case @execution_status.status do
  #                                     :completed -> "bg-success"
  #                                     :failed -> "bg-error"
  #                                     :running -> "bg-warning"
  #                                     _ -> "bg-primary"
  #                                   end
  #                                 ]}
  #                                 style={"width: #{min(100, round(@execution_status.completed_steps / @execution_status.total_steps * 100))}%"}
  #                               >
  #                               </div>
  #                             </div>
  #                           </div>
  #                         <% end %>
  #                         <!-- Execution timing -->
  #                         <%= if @execution_status.started_at do %>
  #                           <div class="mt-1 text-xs text-base-content/50">
  #                             <%= if @execution_status.completed_at do %>
  #                               Completed in {calculate_execution_duration(@execution_status)}
  #                             <% else %>
  #                               Started {format_relative_time(@execution_status.started_at)}
  #                             <% end %>
  #                           </div>
  #                         <% end %>
  #                       </div>
  #                     <% end %>
  #                     <!-- SSE Connection Status -->
  #                     <%= if @streaming do %>
  #                       <div class="border-t border-base-300 px-4 py-1 bg-info/10">
  #                         <div class="flex items-center gap-2 text-xs text-info">
  #                           <div class="w-2 h-2 bg-info rounded-full animate-pulse"></div>
  #                           <span>Connected to agent stream</span>
  #                         </div>
  #                       </div>
  #                     <% end %>
  #                     <!-- Message Input -->
  #                     <div class="border-t border-base-300 p-4">
  #                       <form phx-submit="send_chat_message" class="flex gap-2">
  #                         <input
  #                           type="text"
  #                           name="message"
  #                           placeholder="Type your test message..."
  #                           class="input input-bordered flex-1"
  #                           disabled={@streaming || !@selected_agent_id}
  #                         />
  #                         <button
  #                           type="submit"
  #                           class="btn btn-primary"
  #                           disabled={@streaming || !@selected_agent_id}
  #                         >
  #                           {if @streaming, do: "Sending...", else: "Send"}
  #                         </button>
  #                       </form>
  #                       <!-- Error Display with Recovery Options -->
  #                       <%= if @error_info do %>
  #                         <.live_component
  #                           module={AgentWebWeb.ErrorDisplayComponent}
  #                           id="chat-error"
  #                           error={@error_info.message}
  #                           error_type={@error_info.type}
  #                           context={@error_info.context}
  #                           recovery_actions={@error_info.recovery_actions}
  #                           dismissible={true}
  #                           class="mt-2"
  #                         />
  #                       <% end %>
  #                     </div>
  #                   </div>
  #                 </div>
  #               </div>
  #             </div>
  #           <% end %>
  #         </div>
  #       </div>
  #     </Layouts.app>
  #   </div>
  #   """
  # end

  # Handle form submission for chat messages
  @impl true
  def handle_event("send_chat_message", %{"message" => message}, socket) do
    if String.trim(message) != "" && socket.assigns.selected_agent_id do
      conversation_id = generate_conversation_id(socket.assigns.selected_agent_id)
      context = build_conversation_context(socket.assigns.chat_messages)

      # Send message to self for processing
      send(self(), {:chat_send_message, message, conversation_id, context})
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # Private helper functions

  defp get_selected_agent_name(assigns) do
    if assigns.selected_agent_id && assigns.available_agents != [] do
      case Enum.find(assigns.available_agents, &(&1.id == assigns.selected_agent_id)) do
        nil -> assigns.selected_agent_id
        agent -> agent.name || agent.id
      end
    else
      "None"
    end
  end

  defp generate_conversation_id(agent_id) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    "chat_#{agent_id}_#{timestamp}"
  end

  # Add empty_state component helper
  attr :title, :string, required: true
  attr :message, :string, required: true
  attr :icon, :string, required: true
  slot :actions

  defp empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-12 text-center">
      <.icon name={@icon} class="size-12 text-base-content/30 mb-4" />
      <h3 class="text-lg font-semibold text-base-content/70 mb-2">{@title}</h3>
      <p class="text-sm text-base-content/50 max-w-md mb-4">{@message}</p>
      <%= if @actions != [] do %>
        <div class="flex gap-2">
          {render_slot(@actions)}
        </div>
      <% end %>
    </div>
    """
  end

  defp build_conversation_context(messages) do
    %{
      message_count: length(messages),
      last_user_message: get_last_user_message(messages),
      conversation_topics: extract_topics(messages)
    }
  end

  defp get_last_user_message(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find(&(&1["role"] == "user"))
    |> case do
      nil -> nil
      msg -> msg["content"]
    end
  end

  defp format_error_message(err) do
    case err do
      %{"message" => msg} when is_binary(msg) ->
        "❌ **Agent Error**: #{msg}\n\n*This error occurred during workflow execution. You can try sending your message again or rephrase your request.*"

      %{"type" => "timeout"} ->
        "⏱️ **Timeout Error**: The agent took too long to respond.\n\n*This might be due to high server load. Please try again in a moment.*"

      %{"type" => "connection_error"} ->
        "🔌 **Connection Error**: Unable to connect to the agent service.\n\n*Please check your connection and try again.*"

      %{"type" => "validation_error", "details" => details} ->
        "⚠️ **Validation Error**: #{details}\n\n*Please check your input and try again with a different message.*"

      _ ->
        "❌ **Unexpected Error**: Something went wrong during processing.\n\n*Please try again or contact support if the issue persists.*"
    end
  end

  defp format_user_error(err) do
    ErrorHandler.format_user_error(err)
  end

  defp is_recoverable_error(err) do
    case err do
      %{"type" => type} when type in ["timeout", "connection_error"] ->
        true

      %{"message" => msg} when is_binary(msg) ->
        String.contains?(msg, ["retry", "temporary", "transient"])

      _ ->
        false
    end
  end

  defp extract_topics(messages) do
    # Simple topic extraction - could be enhanced
    messages
    |> Enum.filter(&(&1["role"] == "user"))
    |> Enum.map(& &1["content"])
    # Last 3 user messages for context
    |> Enum.take(-3)
  end

  defp build_conversation_history(existing_messages, new_message, _context) do
    # Convert existing messages to the format expected by the agent
    history_messages =
      existing_messages
      |> Enum.map(fn msg ->
        %{"role" => msg["role"], "content" => msg["content"]}
      end)

    # Add the new user message
    history_messages ++ [%{"role" => "user", "content" => new_message}]
  end

  defp update_execution_status(socket, status, step_name \\ nil) do
    current_status = socket.assigns.execution_status

    updated_status =
      case status do
        :running ->
          %{
            current_status
            | status: :running,
              started_at: DateTime.utc_now(),
              current_step_name: step_name || "Processing message..."
          }

        :completed ->
          %{
            current_status
            | status: :completed,
              completed_at: DateTime.utc_now(),
              completed_steps: current_status.total_steps,
              current_step_name: nil
          }

        :failed ->
          %{
            current_status
            | status: :failed,
              completed_at: DateTime.utc_now(),
              current_step_name: nil
          }

        :idle ->
          %{current_status | status: :idle, current_step_name: nil}
      end

    assign(socket, :execution_status, updated_status)
  end

  defp update_workflow_node_status(socket, step_id, status, metadata \\ %{}) do
    if socket.assigns.workflow_graph do
      # Update the execution state for the workflow graph
      execution_state = socket.assigns[:workflow_execution_state] || %{}

      node_state = Map.get(execution_state, step_id, %{})

      updated_node_state =
        node_state
        |> Map.put(:status, status)
        |> Map.merge(metadata)

      updated_execution_state = Map.put(execution_state, step_id, updated_node_state)

      assign(socket, :workflow_execution_state, updated_execution_state)
    else
      socket
    end
  end

  defp increment_completed_steps(socket) do
    current_status = socket.assigns.execution_status
    updated_status = %{current_status | completed_steps: current_status.completed_steps + 1}
    assign(socket, :execution_status, updated_status)
  end

  defp extract_workflow_progress(meta) do
    # Extract workflow progress information from SSE metadata
    # This would be populated by the workflow engine during execution
    case meta do
      %{"workflow_progress" => progress} -> progress
      %{"workflow" => workflow_data} -> workflow_data
      _ -> nil
    end
  end

  defp extract_workflow_error(err) do
    # Extract workflow-specific error information
    case err do
      %{"workflow_step" => step_id, "workflow_error" => error} ->
        %{step_id: step_id, error: error}

      %{"step_id" => step_id, "error" => error} ->
        %{step_id: step_id, error: error}

      _ ->
        nil
    end
  end

  defp maybe_update_workflow_progress(socket, nil), do: socket

  defp maybe_update_workflow_progress(socket, progress) do
    # Update workflow progress based on metadata from SSE events
    case progress do
      %{"current_step" => step_id, "status" => "running"} ->
        socket
        |> update_workflow_node_status(step_id, :running)
        |> update_execution_status(:running, step_id)

      %{"completed_steps" => completed_steps} when is_list(completed_steps) ->
        Enum.reduce(completed_steps, socket, fn step_data, acc_socket ->
          step_id = Map.get(step_data, "step_id")
          execution_time = Map.get(step_data, "execution_time_ms")

          if step_id do
            update_workflow_node_status(acc_socket, step_id, :completed, %{
              execution_time_ms: execution_time
            })
          else
            acc_socket
          end
        end)

      _ ->
        socket
    end
  end

  defp maybe_update_workflow_error(socket, nil), do: socket

  defp maybe_update_workflow_error(socket, %{step_id: step_id, error: error}) do
    update_workflow_node_status(socket, step_id, :failed, %{error: error})
  end

  defp update_workflow_progress(socket, step_name, status, step_id, execution_time_ms, error) do
    Logger.info("workflow.step_execution", %{
      step_id: step_id,
      step_name: step_name,
      status: status,
      execution_time_ms: execution_time_ms,
      has_error: not is_nil(error),
      error: error
    })

    socket =
      case status do
        "starting" ->
          socket
          |> assign(:current_step_id, step_id)
          |> update_workflow_node_status(step_id, :running)
          |> update_execution_status(:running, step_name)

        "completed" ->
          metadata = if execution_time_ms, do: %{execution_time_ms: execution_time_ms}, else: %{}

          socket
          |> assign(:current_step_id, nil)
          |> update_workflow_node_status(step_id, :completed, metadata)
          |> increment_completed_steps()

        "failed" ->
          metadata = if error, do: %{error: error}, else: %{}

          socket
          |> assign(:current_step_id, nil)
          |> update_workflow_node_status(step_id, :failed, metadata)
          |> update_execution_status(:failed)

        "skipped" ->
          socket
          |> assign(:current_step_id, nil)
          |> update_workflow_node_status(step_id, :skipped)
          |> increment_completed_steps()

        _ ->
          socket
      end

    broadcast_workflow_update(socket, :step_execution, step_id, %{
      step_name: step_name,
      status: status,
      execution_time_ms: execution_time_ms,
      error: error
    })
  end

  defp maybe_update_execution_status(socket, status, step_name) do
    case status do
      "starting" ->
        update_execution_status(socket, :running, step_name)

      "failed" ->
        update_execution_status(socket, :failed)

      _ ->
        socket
    end
  end

  defp calculate_execution_duration(execution_status) do
    if execution_status.started_at && execution_status.completed_at do
      duration_ms =
        DateTime.diff(execution_status.completed_at, execution_status.started_at, :millisecond)

      cond do
        duration_ms < 1000 -> "#{duration_ms}ms"
        duration_ms < 60_000 -> "#{Float.round(duration_ms / 1000, 1)}s"
        true -> "#{Float.round(duration_ms / 60_000, 1)}m"
      end
    else
      "unknown"
    end
  end

  defp format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime, :second)

    cond do
      diff_seconds < 60 -> "#{diff_seconds}s ago"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      true -> "#{div(diff_seconds, 3600)}h ago"
    end
  end

  defp create_user_message(content, agent_id) do
    %{
      "id" => generate_message_id(),
      "role" => "user",
      "content" => content,
      "timestamp" => format_timestamp(DateTime.utc_now()),
      "agent_id" => agent_id
    }
  end

  defp create_assistant_message(content, metadata) do
    # Create assistant message with clean LLM response content only
    # Content should not contain any workflow progress indicators or step execution status
    base_message = %{
      "id" => generate_message_id(),
      "role" => "assistant",
      "content" => content,
      "timestamp" => format_timestamp(DateTime.utc_now()),
      "workflow_id" => Map.get(metadata, :workflow_id),
      "execution_time_ms" => Map.get(metadata, :execution_time_ms),
      "token_count" => Map.get(metadata, :token_count),
      "run_id" => Map.get(metadata, :run_id),
      "trace_id" => Map.get(metadata, :trace_id)
    }

    # Add workflow execution summary if available
    workflow_summary = build_workflow_summary(metadata)

    if workflow_summary do
      Map.put(base_message, "workflow_summary", workflow_summary)
    else
      base_message
    end
  end

  defp build_workflow_summary(metadata) do
    case metadata do
      %{workflow_steps: steps, total_execution_time: total_time} when is_list(steps) ->
        %{
          "total_steps" => length(steps),
          "total_execution_time_ms" => total_time,
          "steps_summary" =>
            Enum.map(steps, fn step ->
              %{
                "name" => Map.get(step, :name, "Unknown"),
                "duration_ms" => Map.get(step, :duration_ms, 0),
                "status" => Map.get(step, :status, "completed")
              }
            end)
        }

      _ ->
        nil
    end
  end

  defp generate_message_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp format_timestamp(datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_string()
    |> String.replace("Z", " UTC")
  end

  defp load_available_agents(socket) do
    case fetch_agents() do
      {:ok, agents} ->
        socket
        |> assign(:available_agents, agents)
        |> assign(:error_info, nil)

      {:error, reason} ->
        error_info = ErrorHandler.analyze_error(reason, :agent_selection)

        socket
        |> assign(:available_agents, [])
        |> assign(:error_info, error_info)
    end
  end

  defp fetch_agents do
    try do
      store = AgentStoreDI.impl!()
      store.list(status: "active")
    rescue
      e ->
        {:error, "Agent store unavailable: #{Exception.message(e)}"}
    end
  end

  defp load_agent_workflow(socket, agent_id) do
    require Logger
    Logger.info("[AgentTestingLive] Loading workflow for agent: #{agent_id}")

    case fetch_agent_details(agent_id) do
      {:ok, agent} ->
        Logger.info("[AgentTestingLive] Agent loaded: #{inspect(agent.id)}")
        Logger.info("[AgentTestingLive] Agent metadata: #{inspect(agent.metadata)}")

        case load_workflow_graph(agent) do
          {:ok, workflow_graph} ->
            Logger.info(
              "[AgentTestingLive] Workflow loaded successfully: #{inspect(workflow_graph.id)}"
            )

            socket
            |> assign(:workflow_graph, workflow_graph)
            |> assign(:loading, false)
            |> assign(:error_info, nil)
            |> update_execution_status_for_workflow(workflow_graph)

          {:error, reason} ->
            Logger.error("[AgentTestingLive] Failed to load workflow: #{inspect(reason)}")
            error_info = ErrorHandler.analyze_error(reason, :workflow)

            socket
            |> assign(:workflow_graph, nil)
            |> assign(:loading, false)
            |> assign(:error_info, error_info)
        end

      {:error, reason} ->
        Logger.error("[AgentTestingLive] Failed to load agent: #{inspect(reason)}")
        error_info = ErrorHandler.analyze_error(reason, :agent_selection)

        socket
        |> assign(:workflow_graph, nil)
        |> assign(:loading, false)
        |> assign(:error_info, error_info)
    end
  end

  defp format_workflow_error(reason, agent) do
    case reason do
      "no_workflows_configured" ->
        "Agent '#{agent.name || agent.id}' has no workflows configured. Try seeding test agents or configuring workflows for this agent."

      "workflow_not_found" ->
        "The workflow configured for agent '#{agent.name || agent.id}' could not be found in the registry."

      "rag_workflow_not_found" ->
        "The RAG conversation workflow is not available. Please ensure the workflow engine is properly initialized."

      "no_rag_workflows_available" ->
        "Neither RAG conversation nor RAG history workflows are available. Please ensure the workflow engine is properly initialized."

      other ->
        "Failed to load workflow: #{other}"
    end
  end

  defp update_execution_status_for_workflow(socket, workflow_spec) do
    total_steps = map_size(workflow_spec.nodes)

    execution_status = %{
      status: :idle,
      started_at: nil,
      completed_at: nil,
      total_steps: total_steps,
      completed_steps: 0,
      current_step_name: nil
    }

    assign(socket, :execution_status, execution_status)
  end

  defp reset_workflow_state(socket) do
    socket
    |> assign(:workflow_graph, nil)
    |> assign(:workflow_execution_state, %{})
    |> assign(:chat_messages, [])
    |> assign(:execution_status, %{
      status: :idle,
      started_at: nil,
      completed_at: nil,
      total_steps: 0,
      completed_steps: 0,
      current_step_name: nil
    })
  end

  defp fetch_agent_details(agent_id) do
    try do
      store = AgentStoreDI.impl!()
      store.get_latest(agent_id)
    rescue
      e ->
        {:error, "Failed to fetch agent: #{Exception.message(e)}"}
    end
  end

  defp load_workflow_graph(agent) do
    try do
      # Try to get the agent's workflow specification
      case get_agent_workflow_spec(agent) do
        {:ok, workflow_spec} ->
          {:ok, workflow_spec}

        {:error, _reason} ->
          # Fallback: create a sample workflow graph for demonstration
          create_sample_workflow_graph()
      end
    rescue
      e ->
        {:error, "Failed to load workflow graph: #{Exception.message(e)}"}
    end
  end

  defp get_agent_workflow_spec(agent) do
    require Logger
    Logger.info("[AgentTestingLive] Getting workflow spec for agent: #{agent.id}")

    # Try multiple approaches to get workflow from agent
    cond do
      # Check if agent has workflows in metadata
      has_workflows_in_metadata?(agent) ->
        Logger.info("[AgentTestingLive] Agent has workflows in metadata")
        get_workflow_from_metadata(agent)

      # Check if agent has a specific workflow configuration
      has_workflow_config?(agent) ->
        Logger.info("[AgentTestingLive] Agent has workflow config")
        get_workflow_from_config(agent)

      # For test agents, try to get the RAG history workflow
      is_test_agent?(agent) ->
        Logger.info("[AgentTestingLive] Agent is test agent, using RAG workflow")
        get_rag_history_workflow()

      # Default case - no workflow found
      true ->
        Logger.error("[AgentTestingLive] No workflow configuration found for agent")
        {:error, "no_workflows_configured"}
    end
  end

  defp has_workflows_in_metadata?(agent) do
    case Map.get(agent, :metadata) do
      %{"workflows" => workflows} when is_list(workflows) and workflows != [] -> true
      _ -> false
    end
  end

  defp get_workflow_from_metadata(agent) do
    require Logger
    workflows = agent.metadata["workflows"]
    workflow_id = List.first(workflows)
    Logger.info("[AgentTestingLive] Getting workflow from metadata: #{inspect(workflow_id)}")

    # Convert string workflow ID to atom for registry lookup
    workflow_atom = String.to_existing_atom(workflow_id)
    Logger.info("[AgentTestingLive] Converted to atom: #{inspect(workflow_atom)}")

    case AgentCore.WorkflowEngine.Registry.get_workflow(workflow_atom) do
      {:ok, spec} ->
        Logger.info("[AgentTestingLive] Workflow found: #{inspect(spec.id)}")
        {:ok, spec}

      {:error, reason} ->
        Logger.error("[AgentTestingLive] Workflow not found: #{inspect(reason)}")
        {:error, "workflow_not_found"}
    end
  rescue
    ArgumentError ->
      Logger.error("[AgentTestingLive] Invalid workflow ID - ArgumentError")
      {:error, "invalid_workflow_id"}
  end

  defp has_workflow_config?(agent) do
    case Map.get(agent, :workflows) do
      workflows when is_list(workflows) and workflows != [] -> true
      _ -> false
    end
  end

  defp get_workflow_from_config(agent) do
    [workflow_id | _] = Map.get(agent, :workflows)

    # Convert string workflow ID to atom for registry lookup
    workflow_atom =
      if is_atom(workflow_id), do: workflow_id, else: String.to_existing_atom(workflow_id)

    case AgentCore.WorkflowEngine.Registry.get_workflow(workflow_atom) do
      {:ok, spec} -> {:ok, spec}
      {:error, _} -> {:error, "workflow_not_found"}
    end
  rescue
    ArgumentError ->
      {:error, "invalid_workflow_id"}
  end

  defp is_test_agent?(agent) do
    case Map.get(agent, :metadata) do
      %{"test_mode" => true} -> true
      _ -> false
    end
  end

  defp get_rag_history_workflow do
    # Try to get the RAG conversation workflow which is the new default
    case AgentCore.WorkflowEngine.Registry.get_workflow(:rag_conversation) do
      {:ok, spec} ->
        {:ok, spec}

      {:error, _} ->
        # Fallback to history_rag if rag_conversation is not available
        case AgentCore.WorkflowEngine.Registry.get_workflow(:history_rag) do
          {:ok, spec} -> {:ok, spec}
          {:error, _} -> {:error, "no_rag_workflows_available"}
        end
    end
  end

  defp create_sample_workflow_graph do
    # Create a sample workflow for demonstration purposes
    sample_spec = %{
      id: :sample_workflow,
      version: 1,
      entry: :start,
      exits: [:done],
      nodes: %{
        start: %{step: "SampleStartStep", opts: %{}},
        process: %{step: "SampleProcessStep", opts: %{}},
        validate: %{step: "SampleValidateStep", opts: %{}},
        done: %{step: "SampleDoneStep", opts: %{}}
      },
      edges: [
        %{from: :start, to: :process, when: {:always}},
        %{from: :process, to: :validate, when: {:decision, :success, true}},
        %{from: :validate, to: :done, when: {:always}}
      ]
    }

    {:ok, sample_spec}
  end

  # Integration helper functions

  defp update_chat_interface_for_agent(socket, agent_id) do
    # Find the selected agent details
    selected_agent = Enum.find(socket.assigns.available_agents, &(&1.id == agent_id))

    socket
    |> assign(:selected_agent, selected_agent)
    # Clear messages when switching agents
    |> assign(:chat_messages, [])
  end

  defp broadcast_workflow_update(socket, event_type, step_id, data) do
    # Broadcast workflow updates to any listening components
    # This could be used for real-time updates to external monitoring systems
    Phoenix.PubSub.broadcast(
      AgentWeb.PubSub,
      "workflow_updates:#{socket.assigns.selected_agent_id}",
      {:workflow_update, event_type, step_id, data}
    )

    socket
  end

  defp generate_execution_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
