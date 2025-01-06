defmodule HiveTest do
  use ExUnit.Case
  doctest Hive

  setup do
    Application.ensure_all_started(:hive)
    on_exit(fn -> Application.stop(:hive) end)
    :ok
  end
end
