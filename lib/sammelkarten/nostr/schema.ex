defmodule Sammelkarten.Nostr.Schema do
  @moduledoc """
  Validation of Sammelkarten custom Nostr event kinds and their tag/field rules.

  Each validate/1 call returns {:ok, event} if all constraints are met else
  {:error, issues}. Issues are atoms or {field, reason} tuples.
  """

  alias Sammelkarten.Nostr.Event

  @card_definition 32121
  @user_collection 32122
  @trade_offer 32123
  @trade_execution 32124
  @price_alert 32125
  @portfolio_snapshot 32126
  @trade_cancel 32127

  @type issue :: atom | {atom, term}

  @spec validate(Event.t()) :: {:ok, Event.t()} | {:error, [issue]}
  def validate(%Event{} = ev) do
    issues =
      basic(ev) ++
        case ev.kind do
          @card_definition -> card_definition(ev)
          @user_collection -> user_collection(ev)
          @trade_offer -> trade_offer(ev)
          @trade_execution -> trade_execution(ev)
          @price_alert -> price_alert(ev)
          @portfolio_snapshot -> portfolio_snapshot(ev)
          @trade_cancel -> trade_cancel(ev)
          _ -> []
        end

    case Enum.uniq(issues) do
      [] -> {:ok, ev}
      list -> {:error, list}
    end
  end

  # --- Generic helpers ---
  defp basic(ev) do
    []
    |> require(ev.pubkey, :pubkey)
    |> require(is_integer(ev.created_at), :created_at)
    |> require(is_integer(ev.kind), :kind)
    |> require(is_list(ev.tags), :tags)
  end

  defp require(issues, true, _), do: issues
  defp require(issues, value, field) when value in [nil, false], do: [field | issues]
  defp require(issues, _value, _field), do: issues

  defp tag_values(ev, name) do
    Enum.flat_map(ev.tags, fn
      [^name | rest] -> [Enum.at(rest, 0)]
      _ -> []
    end)
  end

  defp first_tag(ev, name), do: tag_values(ev, name) |> List.first()
  defp has_tag?(ev, name), do: first_tag(ev, name) != nil

  defp numeric?(nil), do: false

  defp numeric?(s) when is_binary(s) do
    case Integer.parse(s) do
      {_, ""} -> true
      _ -> false
    end
  end

  defp numeric?(_), do: false

  defp positive_int?(s) when is_binary(s) do
    numeric?(s) and String.to_integer(s) > 0
  end

  defp positive_int?(_), do: false

  # --- Kind specific rules ---
  defp card_definition(ev) do
    d = first_tag(ev, "d")

    []
    |> require(String.match?(to_string(d), ~r/^card:.+/), :d_tag)
    |> require(has_tag?(ev, "name"), :name_tag)
    |> require(has_tag?(ev, "rarity"), :rarity_tag)
  end

  defp user_collection(ev) do
    d = first_tag(ev, "d")
    require([], String.match?(to_string(d), ~r/^collection:.+/), :d_tag)
  end

  defp trade_offer(ev) do
    type = first_tag(ev, "type")
    price = first_tag(ev, "price")
    exchange_card = first_tag(ev, "exchange_card")
    quantity = first_tag(ev, "quantity")
    expires_at = first_tag(ev, "expires_at")

    []
    |> require(has_tag?(ev, "card"), :card_tag)
    |> require(type in ["buy", "sell", "exchange"], {:type, :invalid})
    |> require(price || exchange_card, :price_or_exchange_required)
    |> require(if(price, do: positive_int?(price), else: true), {:price, :invalid})
    |> require(positive_int?(quantity), {:quantity, :invalid})
    |> require(if(expires_at, do: numeric?(expires_at), else: true), {:expires_at, :invalid})
  end

  defp trade_execution(ev) do
    []
    |> require(has_tag?(ev, "offer_id"), :offer_id)
    |> require(has_tag?(ev, "buyer"), :buyer)
    |> require(has_tag?(ev, "seller"), :seller)
    |> require(has_tag?(ev, "card"), :card)
    |> require(positive_int?(first_tag(ev, "quantity")), {:quantity, :invalid})
    |> require(positive_int?(first_tag(ev, "price")), {:price, :invalid})
  end

  defp price_alert(ev) do
    d = first_tag(ev, "d")
    direction = first_tag(ev, "direction")
    threshold = first_tag(ev, "threshold")

    []
    |> require(String.match?(to_string(d), ~r/^alert:.+:(above|below)$/), :d_tag)
    |> require(has_tag?(ev, "card"), :card_tag)
    |> require(direction in ["above", "below"], {:direction, :invalid})
    |> require(positive_int?(threshold), {:threshold, :invalid})
  end

  defp portfolio_snapshot(ev) do
    d = first_tag(ev, "d")

    []
    |> require(String.match?(to_string(d), ~r/^portfolio:.+/), :d_tag)
    |> require(numeric?(first_tag(ev, "total_value")), {:total_value, :invalid})
    |> require(numeric?(first_tag(ev, "card_count")), {:card_count, :invalid})
  end

  defp trade_cancel(ev) do
    has_e =
      Enum.any?(ev.tags, fn
        ["e", _id | rest] -> rest == ["cancel"] or rest == []
        _ -> false
      end)

    require([], has_e, :e_tag)
  end
end
