defmodule AgentCore.Llm.RunSnapshots do
  import Bitwise
  alias AgentCore.Llm.{InvocationConfig, RunSnapshot}

  @policy_version "merge_policy.v1"

  @type meta :: %{
          optional(:trace_id) => Ecto.UUID.t() | String.t(),
          optional(:parent_run_id) => Ecto.UUID.t() | String.t() | nil,
          optional(:phase) => String.t() | nil
        }

  @spec from_config(InvocationConfig.t(), map() | nil, meta() | nil) :: RunSnapshot.t()
  def from_config(%InvocationConfig{} = cfg, canonical_overrides \\ nil, meta \\ nil) do
    meta = meta || %{}

    run_id = uuid4()

    trace_id =
      case Map.get(meta, :trace_id) do
        nil -> uuid4()
        tid -> tid
      end

    %RunSnapshot{
      run_id: run_id,
      trace_id: trace_id,
      parent_run_id: Map.get(meta, :parent_run_id),
      phase: Map.get(meta, :phase),

      fingerprint: cfg.fingerprint,
      profile_id: cfg.profile_id,
      profile_name: cfg.profile_name,
      provider: cfg.provider,
      model: cfg.model,
      policy_version: @policy_version,
      resolved_at: cfg.resolved_at,
      overrides: canonical_overrides,
      invocation_config: invocation_config_to_map(cfg)
    }
  end

  defp invocation_config_to_map(%InvocationConfig{} = cfg) do
    %{
      profile_id: cfg.profile_id,
      profile_name: cfg.profile_name,
      provider: cfg.provider,
      model: cfg.model,
      generation: cfg.generation,
      budgets: cfg.budgets,
      tools: cfg.tools,
      stop_list: cfg.stop_list,
      overrides: cfg.overrides,
      fingerprint: cfg.fingerprint,
      resolved_at: cfg.resolved_at
    }
  end


  # UUIDv4 without Ecto
  defp uuid4 do
    <<a1::32, a2::16, a3::16, a4::16, a5::48>> = :crypto.strong_rand_bytes(16)

    a3 = (a3 &&& 0x0FFF) ||| 0x4000
    a4 = (a4 &&& 0x3FFF) ||| 0x8000

    :io_lib.format(
      "~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b",
      [a1, a2, a3, a4, a5]
    )
    |> IO.iodata_to_binary()
  end
end
