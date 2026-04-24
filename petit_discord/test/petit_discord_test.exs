defmodule PetitDiscordTest do
  use ExUnit.Case
  doctest PetitDiscord

  test "greets the world" do
    assert PetitDiscord.hello() == :world
  end
end
