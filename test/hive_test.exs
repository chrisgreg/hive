defmodule HiveTest do
  use ExUnit.Case
  doctest Hive

  test "greets the world" do
    assert Hive.hello() == :world
  end
end
