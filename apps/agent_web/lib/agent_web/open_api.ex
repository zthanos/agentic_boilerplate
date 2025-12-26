defmodule AgentWeb.OpenApi do
  alias OpenApiSpex.{Info, OpenApi, Paths, Server}
  alias AgentWebWeb.{Endpoint, Router}
  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      openapi: "3.0.0",
      info: %Info{
        title: "Agent Web API",
        version: "1.0.0",
        description: "API for Agent Web LLM execution and run management"
      },
      servers: [
        Server.from_endpoint(Endpoint)
      ],
      paths: Paths.from_router(Router)
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
