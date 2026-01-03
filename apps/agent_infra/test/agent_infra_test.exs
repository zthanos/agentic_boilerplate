defmodule AgentInfraTest do
  use ExUnit.Case
  doctest AgentInfra

  test "greets the world" do
    assert AgentInfra.hello() == :world
  end
end
