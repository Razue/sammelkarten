defmodule Sammelkarten.Formatter do
  @moduledoc """
  Number formatting utilities for German locale with Bitcoin sats currency.
  Converts American decimal point format (1,234.00) to German comma format (1.234,00).
  """

  @doc """
  Format a number in German locale with thousands separator, no decimals.
  
  ## Examples
  
      iex> Sammelkarten.Formatter.format_german_number("1234.50")
      "1.234"
      
      iex> Sammelkarten.Formatter.format_german_number("12.34")
      "12"
      
      iex> Sammelkarten.Formatter.format_german_number("1000000.00")
      "1.000.000"
  """
  def format_german_number(number_string) when is_binary(number_string) do
    # Split at decimal point and only keep integer part (no rounding)
    case String.split(number_string, ".") do
      [integer_part] ->
        # No decimal part
        add_thousands_separator(integer_part)
      
      [integer_part, _decimal_part] ->
        # Ignore decimal part completely (truncate)
        add_thousands_separator(integer_part)
    end
  end

  @doc """
  Format a Decimal to German number format without decimals.
  """
  def format_german_decimal(%Decimal{} = decimal) do
    # Truncate to integer (no rounding) using round with :down mode
    decimal
    |> Decimal.round(0, :down)
    |> Decimal.to_integer()
    |> Integer.to_string()
    |> add_thousands_separator()
  end

  @doc """
  Format price in sats to German sats format without decimals.
  
  ## Examples
  
      iex> Sammelkarten.Formatter.format_german_price(1234)
      "1.234 sats"
  """
  def format_german_price(price_sats) when is_integer(price_sats) do
    # Format full sats number with thousands separator
    add_thousands_separator(Integer.to_string(price_sats)) <> " sats"
  end

  @doc """
  Format percentage change with German decimal format.
  
  ## Examples
  
      iex> Sammelkarten.Formatter.format_german_percentage(12.34)
      "+12,34%"
      
      iex> Sammelkarten.Formatter.format_german_percentage(-5.67)
      "-5,67%"
  """
  def format_german_percentage(percentage) when is_float(percentage) do
    sign = if percentage >= 0, do: "+", else: ""
    formatted_number = 
      percentage
      |> :erlang.float_to_binary(decimals: 2)
      |> String.replace(".", ",")
    
    "#{sign}#{formatted_number}%"
  end

  # Private helper to add thousands separator (dots in German format)
  defp add_thousands_separator(integer_string) do
    integer_string
    |> String.reverse()
    |> String.to_charlist()
    |> Enum.chunk_every(3)
    |> Enum.map(&List.to_string/1)
    |> Enum.join(".")
    |> String.reverse()
  end
end