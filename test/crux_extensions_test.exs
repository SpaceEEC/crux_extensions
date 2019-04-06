defmodule Crux.ExtensionsTest do
  use ExUnit.Case
  doctest Crux.Extensions

  test "greets the world" do
    assert Crux.Extensions.hello() == :world
  end
end
