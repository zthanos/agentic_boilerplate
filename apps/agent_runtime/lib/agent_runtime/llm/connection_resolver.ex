defmodule AgentRuntime.Llm.ConnectionResolver do
  @moduledoc """
  Resolves provider connection settings from environment variables.

  This is intentionally simple for the current milestone.
  Later, swap implementation to DB-encrypted or KeyVault without changing provider adapters.
  """

  @type t :: %{
          base_url: String.t(),
          api_key: String.t() | nil,
          timeout_ms: non_neg_integer()
        }

  @default_timeout_ms 60_000

  @spec openai_compatible() :: t()
  def openai_compatible do
    %{
      base_url: env("OPENAI_COMPAT_BASE_URL", "http://127.0.0.1:1234"),
      api_key: env("OPENAI_COMPAT_API_KEY", nil) |> normalize_blank(),
      timeout_ms: env_int("OPENAI_COMPAT_TIMEOUT_MS", @default_timeout_ms)
    }
  end

  defp env(key, default), do: System.get_env(key) || default

  defp env_int(key, default) do
    case System.get_env(key) do
      nil -> default
      "" -> default
      v ->
        case Integer.parse(v) do
          {i, _} when i > 0 -> i
          _ -> default
        end
    end
  end

  defp normalize_blank(nil), do: nil
  defp normalize_blank(""), do: nil
  defp normalize_blank(v), do: v
end
