defmodule AgentRuntime.Llm.Client do
  @moduledoc """
  Runtime LLM execution orchestrator.

  Responsibilities:
  - profile lookup
  - resolve invocation
  - build ProviderRequest
  - route & call provider adapter
  """

  alias AgentCore.Llm.{
    Profiles,
    Resolver,
    ProviderRequest
    # ProviderAdapter
  }

  @type chat_message :: map()
  @type overrides :: map()

  @spec chat(Profiles.id(), [chat_message()], overrides()) ::
          {:ok, AgentCore.Llm.ProviderResponse.t()} | {:error, term()}
  def chat(profile_id, messages, overrides \\ %{}) do
    with {:ok, profile} <- fetch_profile(profile_id),
         :ok <- validate_messages(messages),
         {:ok, invocation} <- resolve(profile, overrides),
         {:ok, adapter} <- route(invocation.provider),
         {:ok, response} <- call_provider(adapter, invocation, messages) do
      {:ok, response}
    end
  end

  # -------------------------
  # Steps
  # -------------------------

  defp fetch_profile(id) do
    {:ok, Profiles.get!(id)}
  rescue
    e -> {:error, {:profile_not_found, e}}
  end

  defp resolve(profile, overrides) do
    {:ok, Resolver.resolve(profile, overrides)}
  rescue
    e -> {:error, {:resolve_failed, e}}
  end

  defp call_provider(adapter, invocation, messages) do
    request =
      ProviderRequest.new(
        invocation,
        %{
          type: :chat,
          messages: messages
        }
      )

    adapter.call(request)
  end

  # -------------------------
  # Routing
  # -------------------------

  defp route(:fake), do: {:ok, AgentCore.Llm.Providers.FakeProvider}

  defp route(provider),
    do: {:error, {:unsupported_provider, provider}}

  # -------------------------
  # Validation
  # -------------------------

  defp validate_messages([]), do: {:error, :no_messages}

  defp validate_messages(messages) when is_list(messages) do
    ok? =
      Enum.all?(messages, fn m ->
        role = Map.get(m, :role)
        is_atom(role) and role in [:system, :user, :assistant, :tool]
      end)

    if ok?, do: :ok, else: {:error, :invalid_messages}
  end
end
