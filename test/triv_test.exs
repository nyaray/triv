defmodule TrivTest do
  use ExUnit.Case
  doctest Triv

  test "greets the world" do
    assert Triv.hello() == :world
  end
end
