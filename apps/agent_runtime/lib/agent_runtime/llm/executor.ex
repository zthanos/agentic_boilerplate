defmodule AgentRuntime.Llm.Executor do
  @moduledoc """
  Single entry point for LLM execution.

  Responsible for:
  - resolving InvocationConfig
  - persisting run snapshot
  - run lifecycle (started / finished / failed)
  - provider routing & call
  """

  alias AgentCore.Llm.{Resolver, ProviderRequest}
  # alias AgentCore.Llm.RunSnapshots
  # alias AgentCore.Llm.RunStore.Ecto, as: RunStore
  alias AgentRuntime.Llm.ProviderRouter

  def execute(profile, overrides, input) do
    invocation = Resolver.resolve(profile, overrides)

    request =
      ProviderRequest.new(invocation, input, [], %{
        "profile_id" => to_string(invocation.profile_id),
        "provider" => to_string(invocation.provider),
        "model" => to_string(invocation.model),
        "policy_version" => invocation.policy_version,
        "fingerprint" => invocation.fingerprint
      })

    with {:ok, adapter} <- ProviderRouter.route(invocation.provider),
         {:ok, resp} <- adapter.call(request) do
      {:ok, resp}
    else
      {:error, reason} -> {:error, reason}
    end
  end

end
