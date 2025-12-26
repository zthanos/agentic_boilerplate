defmodule AgentRuntime.Flows.Requirements do
  @moduledoc false

  alias AgentRuntime.Llm.{Client, ProfileSelector}
  alias AgentRuntime.Flows.Requirements.{Parser, Prompt}

  @spec extract([map()], map()) :: {:ok, map()} | {:error, term()}
  def extract(messages, overrides \\ %{}) when is_list(messages) and is_map(overrides) do
    profile_id = ProfileSelector.for(:requirements)

    # prepend system prompt (you can also do this in calling code)
    msgs = [%{role: :system, content: Prompt.system_prompt("en")} | messages]

    with {:ok, resp} <- Client.chat(profile_id, msgs, overrides),
         {:ok, json} <- Parser.parse_and_validate(resp.output_text) do
      {:ok, json}
    end
  end
end
