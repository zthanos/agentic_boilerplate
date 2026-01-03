defmodule AgentRuntime.Performance.BenchmarkTest do
  @moduledoc """
  Performance benchmark tests to ensure no significant regressions after restructuring.
  """
  use ExUnit.Case, async: false

  alias AgentRuntime.Agent

  @moduletag :performance

  describe "performance benchmarks" do
    test "profile creation performance" do
      profile_attrs = %{
        name: "benchmark-profile",
        provider: :openai,
        model: "gpt-4"
      }

      # Warm up
      {:ok, _} = Agent.create_profile(profile_attrs)

      # Benchmark profile creation
      {time_microseconds, {:ok, _profile}} =
        :timer.tc(fn ->
          Agent.create_profile(%{
            profile_attrs
            | name: "benchmark-profile-#{:rand.uniform(10000)}"
          })
        end)

      # Profile creation should complete within reasonable time (< 100ms)
      assert time_microseconds < 100_000,
             "Profile creation took #{time_microseconds}μs, expected < 100ms"
    end

    test "run creation performance" do
      # First create a profile
      profile_attrs = %{
        name: "benchmark-run-profile",
        provider: :openai,
        model: "gpt-3.5-turbo"
      }

      {:ok, profile} = Agent.create_profile(profile_attrs)

      run_attrs = %{
        profile_id: profile.id,
        provider: :openai,
        model: "gpt-3.5-turbo",
        policy_version: "1.0",
        resolved_at: DateTime.utc_now()
      }

      # Warm up
      {:ok, _} = Agent.create_run(run_attrs)

      # Benchmark run creation
      {time_microseconds, {:ok, _run}} =
        :timer.tc(fn ->
          Agent.create_run(run_attrs)
        end)

      # Run creation should complete within reasonable time (< 200ms)
      assert time_microseconds < 200_000,
             "Run creation took #{time_microseconds}μs, expected < 200ms"
    end

    test "profile retrieval performance" do
      # Create a profile first
      profile_attrs = %{
        name: "benchmark-retrieval-profile",
        provider: :openai,
        model: "gpt-4"
      }

      {:ok, profile} = Agent.create_profile(profile_attrs)

      # Warm up
      {:ok, _} = Agent.get_profile(profile.id)

      # Benchmark profile retrieval
      {time_microseconds, {:ok, _retrieved_profile}} =
        :timer.tc(fn ->
          Agent.get_profile(profile.id)
        end)

      # Profile retrieval should be very fast (< 50ms)
      assert time_microseconds < 50_000,
             "Profile retrieval took #{time_microseconds}μs, expected < 50ms"
    end

    test "run status update performance" do
      # Create profile and run first
      profile_attrs = %{
        name: "benchmark-update-profile",
        provider: :openai,
        model: "gpt-3.5-turbo"
      }

      {:ok, profile} = Agent.create_profile(profile_attrs)

      run_attrs = %{
        profile_id: profile.id,
        provider: :openai,
        model: "gpt-3.5-turbo",
        policy_version: "1.0",
        resolved_at: DateTime.utc_now()
      }

      {:ok, run} = Agent.create_run(run_attrs)

      # Warm up
      {:ok, _} = Agent.update_run(run.id, %{status: :running})

      # Reset status for benchmark
      {:ok, _} = Agent.update_run(run.id, %{status: :pending})

      # Benchmark run status update
      {time_microseconds, {:ok, _updated_run}} =
        :timer.tc(fn ->
          Agent.update_run(run.id, %{status: :running})
        end)

      # Run update should be fast (< 100ms)
      assert time_microseconds < 100_000,
             "Run update took #{time_microseconds}μs, expected < 100ms"
    end

    test "bulk operations performance" do
      # Test creating multiple profiles in sequence
      profile_base_attrs = %{
        provider: :openai,
        model: "gpt-3.5-turbo"
      }

      # Benchmark creating 10 profiles
      {time_microseconds, profiles} =
        :timer.tc(fn ->
          Enum.map(1..10, fn i ->
            attrs = Map.put(profile_base_attrs, :name, "bulk-profile-#{i}")
            {:ok, profile} = Agent.create_profile(attrs)
            profile
          end)
        end)

      # Bulk operations should scale reasonably (< 1 second for 10 profiles)
      assert time_microseconds < 1_000_000,
             "Bulk profile creation took #{time_microseconds}μs, expected < 1s"

      assert length(profiles) == 10
    end

    test "memory usage stability" do
      # Test that repeated operations don't cause memory leaks
      initial_memory = :erlang.memory(:total)

      # Perform many operations
      Enum.each(1..100, fn i ->
        profile_attrs = %{
          name: "memory-test-profile-#{i}",
          provider: :openai,
          model: "gpt-3.5-turbo"
        }

        {:ok, profile} = Agent.create_profile(profile_attrs)
        {:ok, _retrieved} = Agent.get_profile(profile.id)
      end)

      # Force garbage collection
      :erlang.garbage_collect()
      Process.sleep(100)

      final_memory = :erlang.memory(:total)
      memory_increase = final_memory - initial_memory

      # Memory increase should be reasonable (< 50MB for 100 operations)
      # 50MB in bytes
      max_increase = 50 * 1024 * 1024

      assert memory_increase < max_increase,
             "Memory increased by #{memory_increase} bytes, expected < #{max_increase}"
    end
  end

  describe "system resource usage" do
    test "database connection efficiency" do
      # Test that operations don't exhaust database connections
      profile_attrs = %{
        name: "db-connection-test",
        provider: :openai,
        model: "gpt-4"
      }

      # Perform many concurrent operations
      tasks =
        Enum.map(1..20, fn i ->
          Task.async(fn ->
            attrs = Map.put(profile_attrs, :name, "concurrent-profile-#{i}")
            Agent.create_profile(attrs)
          end)
        end)

      # All tasks should complete successfully
      results = Task.await_many(tasks, 5000)

      # All operations should succeed
      assert Enum.all?(results, fn
               {:ok, _} -> true
               _ -> false
             end),
             "Some concurrent operations failed"
    end

    test "error handling performance" do
      # Test that error cases don't cause performance degradation

      # Benchmark error case (non-existent profile)
      {time_microseconds, {:error, :not_found}} =
        :timer.tc(fn ->
          Agent.get_profile("non-existent-profile-id")
        end)

      # Error handling should be fast (< 10ms)
      assert time_microseconds < 10_000,
             "Error handling took #{time_microseconds}μs, expected < 10ms"
    end
  end
end
