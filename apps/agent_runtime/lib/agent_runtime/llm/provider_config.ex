defmodule AgentRuntime.Llm.ProviderConfig do
  @moduledoc false

  @type openai_compatible_config :: %{
          base_url: String.t(),
          api_key: String.t() | nil,
          timeout_ms: pos_integer(),
          connect_timeout_ms: pos_integer()
        }

  @default_base_url "http://host.docker.internal:1234/v1"
  @default_timeout_ms 60_000
  @default_connect_timeout_ms 10_000

  @spec openai_compatible(keyword()) :: openai_compatible_config
  def openai_compatible(overrides \\ []) when is_list(overrides) do
    base_url =
      overrides[:base_url] ||
        System.get_env("OPENAI_BASE_URL") ||
        System.get_env("OPENAI_COMPAT_BASE_URL") || # optional backward-compat
        @default_base_url

    api_key =
      overrides
      |> Keyword.get(:api_key, System.get_env("OPENAI_API_KEY") || System.get_env("OPENAI_COMPAT_API_KEY"))
      |> normalize_optional_string()

    timeout_ms =
      overrides[:timeout_ms] ||
        env_int("OPENAI_TIMEOUT_MS") ||
        env_int("OPENAI_COMPAT_TIMEOUT_MS") ||
        @default_timeout_ms

    connect_timeout_ms =
      overrides[:connect_timeout_ms] ||
        env_int("OPENAI_CONNECT_TIMEOUT_MS") ||
        env_int("OPENAI_COMPAT_CONNECT_TIMEOUT_MS") ||
        @default_connect_timeout_ms

    %{
      base_url: base_url,
      api_key: api_key,
      timeout_ms: timeout_ms,
      connect_timeout_ms: connect_timeout_ms
    }
  end

  defp env_int(name) do
    case System.get_env(name) do
      nil -> nil
      "" -> nil
      v ->
        case Integer.parse(v) do
          {i, ""} when i > 0 -> i
          _ -> nil
        end
    end
  end

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(""), do: nil

  defp normalize_optional_string(v) when is_binary(v) do
    case String.trim(v) do
      "" -> nil
      s -> s
    end
  end
end
