defmodule SammelkartenWeb.TradingHelpers do
  @moduledoc """
  Shared helpers for trading tab components (filtering, sorting offers).
  """

  def filter_and_sort_offers(offers, search_query, filter_type, sort_by) do
    offers
    |> filter_by_search(search_query)
    |> filter_by_type(filter_type)
    |> sort_offers(sort_by)
  end

  defp filter_by_search(offers, ""), do: offers

  defp filter_by_search(offers, query) do
    query_lower = String.downcase(query)

    Enum.filter(offers, fn offer ->
      card_name = if Map.has_key?(offer, :card), do: String.downcase(offer.card.name), else: ""
      String.contains?(card_name, query_lower)
    end)
  end

  defp filter_by_type(offers, "all"), do: offers

  defp filter_by_type(offers, filter_type),
    do: Enum.filter(offers, &(&1.offer_type == filter_type))

  defp sort_offers(offers, "newest"), do: Enum.sort_by(offers, & &1.created_at, :desc)
  defp sort_offers(offers, "price_low"), do: Enum.sort_by(offers, & &1.price, :asc)
  defp sort_offers(offers, "price_high"), do: Enum.sort_by(offers, & &1.price, :desc)
  defp sort_offers(offers, _), do: offers
end
