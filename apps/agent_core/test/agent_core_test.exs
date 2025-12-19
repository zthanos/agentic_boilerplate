defmodule AgentCoreTest do
  use ExUnit.Case
  doctest AgentCore

  test "greets the world" do
    assert AgentCore.hello() == :world
  end
end
