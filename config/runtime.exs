import Config

# -----------------------------------------------------------------------------
# Agent Runtime: profile/model routing (runtime-driven)
# -----------------------------------------------------------------------------
config :agent_runtime, AgentRuntime.Llm.ProfileSelector,
  # If nil, resolver must decide (and should record resolution_source)
  default: System.get_env("DEFAULT_LLM_PROFILE_ID"),
  mappings: %{
    # If nil, mapping should be treated as "no mapping"
    requirements: System.get_env("REQ_LLM_PROFILE_ID")
  }

config :agent_runtime, AgentRuntime.Llm.ModelResolver,
  openai_compatible: %{
    # If nil, alias should be treated as "unknown alias"
    local: System.get_env("LOCAL_LLM_MODEL"),
    gpt4mini: System.get_env("GPT4MINI_MODEL")
  }

# -----------------------------------------------------------------------------
# Enable Phoenix server in releases
# -----------------------------------------------------------------------------
if System.get_env("PHX_SERVER") do
  config :agent_web, AgentWebWeb.Endpoint, server: true
end

# -----------------------------------------------------------------------------
# Database config (all envs)
# -----------------------------------------------------------------------------
db_adapter = System.get_env("DB_ADAPTER", "postgres")

case db_adapter do
  "postgres" ->
    database_url =
      System.get_env("DATABASE_URL") ||
        raise """
        environment variable DATABASE_URL is missing.
        Example: ecto://postgres:postgres@localhost:5432/agent_web_dev
        """

    config :agent_web, AgentWeb.Repo,
      url: database_url,
      pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  "sqlite" ->
    sqlite_path =
      System.get_env("SQLITE_PATH") ||
        raise """
        environment variable SQLITE_PATH is missing.
        Example: /data/agent_web.sqlite3
        """

    config :agent_web, AgentWeb.Repo,
      database: sqlite_path,
      pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  other ->
    raise "Unsupported DB_ADAPTER=#{inspect(other)}. Expected 'postgres' or 'sqlite'."
end

# -----------------------------------------------------------------------------
# Provider runtime env (OpenAI-compatible) - available in all envs
# -----------------------------------------------------------------------------
# Many OpenAI-compatible servers expect /v1 as base. Prefer it in runtime.
base_url =
  System.get_env("OPENAI_COMPAT_BASE_URL") ||
    "http://localhost:1234/v1"

base_url =
  if String.ends_with?(base_url, "/v1") do
    base_url
  else
    base_url <> "/v1"
  end

config :agent_runtime, AgentRuntime.Llm.ProviderConfig,
  openai_compatible: [
    base_url: base_url,
    api_key: System.get_env("OPENAI_COMPAT_API_KEY") || "",
    timeout_ms: String.to_integer(System.get_env("OPENAI_COMPAT_TIMEOUT_MS") || "60000"),
    connect_timeout_ms: String.to_integer(System.get_env("OPENAI_COMPAT_CONNECT_TIMEOUT_MS") || "10000")
  ]

# -----------------------------------------------------------------------------
# Production-only runtime configuration
# -----------------------------------------------------------------------------
if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :agent_web, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :agent_web, AgentWebWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base
end
