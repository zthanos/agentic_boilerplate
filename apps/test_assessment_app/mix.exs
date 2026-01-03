defmodule TestAssessmentApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :test_assessment_app,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {TestAssessmentApp.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:agent_core, in_umbrella: true},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},
      {:stream_data, "~> 1.0", only: [:test]},
      {:ex_machina, "~> 2.8", only: :test},
      {:mox, "~> 1.2", only: :test}
    ]
  end
end
