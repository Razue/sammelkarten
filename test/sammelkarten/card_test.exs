defmodule Sammelkarten.CardTest do
  use ExUnit.Case, async: true

  alias Sammelkarten.Card

  test "new/1 creates a card with defaults and overrides" do
    card = Card.new(%{name: "Test", image_path: "/img.png", current_price: 123, rarity: "rare"})
    assert card.name == "Test"
    assert card.image_path == "/img.png"
    assert card.current_price == 123
    assert card.rarity == "rare"
    assert is_binary(card.id)
    assert is_integer(card.price_change_24h)
    assert is_float(card.price_change_percentage)
    assert is_binary(card.description)
    assert %DateTime{} = card.last_updated
  end

  test "generate_id/0 returns a 32-char hex string" do
    id = Card.generate_id()
    assert is_binary(id)
    assert String.length(id) == 32
    assert String.match?(id, ~r/^[0-9a-f]{32}$/)
  end

  test "price_to_decimal/1 converts cents to decimal" do
    assert Card.price_to_decimal(1234) == Decimal.new("12.34")
  end

  test "decimal_to_price/1 converts decimal to cents" do
    assert Card.decimal_to_price(Decimal.new("12.34")) == 1234
  end

  test "rarity_color/1 returns correct color class" do
    assert Card.rarity_color("common") == "text-gray-600"
    assert Card.rarity_color("rare") == "text-blue-600"
    assert Card.rarity_color("epic") == "text-purple-600"
    assert Card.rarity_color("legendary") == "text-yellow-600"
    assert Card.rarity_color("unknown") == "text-gray-600"
  end

  test "price_change_color/1 returns correct color class" do
    assert Card.price_change_color(10.0) == "text-green-600"
    assert Card.price_change_color(-5.0) == "text-red-600"
    assert Card.price_change_color(0.0) == "text-gray-600"
  end

  test "format_price/1 delegates to Formatter.format_german_price/1" do
    assert Card.format_price(1234) == Sammelkarten.Formatter.format_german_price(1234)
  end

  test "format_price_change/1 delegates to Formatter.format_german_percentage/1" do
    assert Card.format_price_change(12.5) ==
             Sammelkarten.Formatter.format_german_percentage(12.5)
  end
end
