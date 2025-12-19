defmodule AgentRuntimeTest do
  use ExUnit.Case
  doctest AgentRuntime

  test "greets the world" do
    assert AgentRuntime.hello() == :world
  end
end
