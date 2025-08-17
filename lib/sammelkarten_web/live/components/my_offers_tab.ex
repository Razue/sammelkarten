defmodule SammelkartenWeb.TradingLive.MyOffersTab do
  defp format_price(price) when is_integer(price),
    do: Sammelkarten.Formatter.format_german_price(price)

  defp format_price(price) when is_float(price),
    do: Sammelkarten.Formatter.format_german_price(trunc(price))

  # Helper for rarity color
  defp rarity_color(rarity) do
    case String.downcase(rarity) do
      "common" -> "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200"
      "uncommon" -> "bg-green-100 text-green-800 dark:bg-green-700 dark:text-green-200"
      "rare" -> "bg-blue-100 text-blue-800 dark:bg-blue-700 dark:text-blue-200"
      "epic" -> "bg-purple-100 text-purple-800 dark:bg-purple-700 dark:text-purple-200"
      "legendary" -> "bg-yellow-100 text-yellow-800 dark:bg-yellow-700 dark:text-yellow-200"
      "mythic" -> "bg-red-100 text-red-800 dark:bg-red-700 dark:text-red-200"
      _ -> "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200"
    end
  end

  use Phoenix.Component

  def my_offers_tab(assigns) do
    ~H"""
    <div>
      <%= if length(@my_offers) == 0 do %>
        <div class="text-center py-12">
          <div class="text-6xl mb-4">📋</div>
          <h3 class="text-heading-sm text-text mb-2">No Active Offers</h3>
          <p class="text-body-md text-secondary">
            You don't have any active trade offers. Create one to start trading!
          </p>
          <button phx-click="change_tab" phx-value-tab="create_offer" class="btn-primary mt-4">
            ➕ Create First Offer
          </button>
        </div>
      <% else %>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
          <%= for offer <- @my_offers do %>
            <%= if Map.has_key?(offer, :card) do %>
              <.link
                navigate={"/#{offer.card.slug}"}
                class="card-grid-item card-professional card-hover block overflow-hidden cursor-pointer border-2 border-blue-200 bg-blue-50 dark:border-blue-700 dark:bg-blue-900/20"
              >
                <div class="aspect-w-3 aspect-h-4 bg-gray-100 dark:bg-gray-700 overflow-hidden">
                  <img
                    src={offer.card.image_path}
                    alt={offer.card.name}
                    class="card-image-hover w-full h-48 object-cover object-top"
                    loading="lazy"
                  />
                </div>
                <div class="p-4">
                  <div class="flex items-start justify-between mb-4">
                    <h3 class="text-heading-md text-gray-900 dark:text-white truncate flex-1">
                      {offer.card.name}
                    </h3>
                    <span class={"ml-2 px-2.5 py-1 text-label-sm rounded-full shrink-0 #{rarity_color(offer.card.rarity)}"}>
                      {offer.card.rarity}
                    </span>
                  </div>
                  <div class="space-y-3">
                    <div class="flex items-center justify-between">
                      <div class="flex items-center space-x-2">
                        <%= cond do %>
                          <% offer.offer_type == "buy" -> %>
                            <span class="text-xl text-green-600">🛒</span>
                            <span class="text-heading-lg text-green-600 dark:text-green-400">
                              {offer.quantity}
                            </span>
                            <span class="text-label-sm text-green-500 dark:text-green-400">
                              {if offer.quantity == 1, do: "card", else: "cards"}
                            </span>
                          <% offer.offer_type == "sell" -> %>
                            <span class="text-xl text-red-600">💰</span>
                            <span class="text-heading-lg text-red-600 dark:text-red-400">
                              {offer.quantity}
                            </span>
                            <span class="text-label-sm text-red-500 dark:text-red-400">
                              {if offer.quantity == 1, do: "card", else: "cards"}
                            </span>
                          <% true -> %>
                            <span class="text-xl text-blue-600">🔄</span>
                            <span class="text-heading-lg text-blue-600 dark:text-blue-400">
                              {offer.quantity}
                            </span>
                            <span class="text-label-sm text-blue-500 dark:text-blue-400">
                              {if offer.quantity == 1, do: "card", else: "cards"}
                            </span>
                        <% end %>
                      </div>
                      <div class="text-right">
                        <div class="text-heading-sm font-semibold text-gray-900 dark:text-white">
                          {format_price(offer.price)}
                        </div>
                        <div class="text-label-xs text-gray-500 dark:text-gray-400">per card</div>
                      </div>
                    </div>
                    <div class="flex items-center justify-between">
                      <div>
                        <div class="text-label-sm text-gray-600 dark:text-gray-400">Total Value</div>
                        <div class="text-heading-xs font-bold text-gray-900 dark:text-white">
                          {format_price(offer.total_value)}
                        </div>
                      </div>
                      <div class="text-right">
                        <div class="text-label-sm text-gray-600 dark:text-gray-400">Status</div>
                        <div class="text-label-sm font-medium text-green-600 dark:text-green-400">
                          ✅ Active
                        </div>
                      </div>
                    </div>
                  </div>
                  <div class="mt-4">
                    <button
                      phx-click="cancel_offer"
                      phx-value-offer_id={offer.id}
                      class="w-full py-3 px-4 bg-red-600 hover:bg-red-700 text-white rounded-lg font-medium text-body-md transition-colors"
                      data-confirm="Are you sure you want to cancel this offer?"
                    >
                      🗑️ Cancel Offer
                    </button>
                  </div>
                </div>
              </.link>
            <% else %>
              <div class="card-grid-item card-professional card-hover block overflow-hidden border-2 border-blue-200 bg-blue-50 dark:border-blue-700 dark:bg-blue-900/20">
                <div class="w-full h-48 bg-muted flex items-center justify-center">
                  <div class="text-6xl text-muted-foreground">?</div>
                </div>
                <div class="p-4">
                  <div class="flex items-start justify-between mb-4">
                    <h3 class="text-heading-md text-gray-900 dark:text-white truncate flex-1">
                      Unknown Card
                    </h3>
                  </div>
                  <div class="space-y-3">
                    <div class="flex items-center justify-between">
                      <div class="flex items-center space-x-2">
                        <%= cond do %>
                          <% offer.offer_type == "buy" -> %>
                            <span class="text-xl text-green-600">🛒</span>
                            <span class="text-heading-lg text-green-600 dark:text-green-400">
                              {offer.quantity}
                            </span>
                            <span class="text-label-sm text-green-500 dark:text-green-400">
                              {if offer.quantity == 1, do: "card", else: "cards"}
                            </span>
                          <% offer.offer_type == "sell" -> %>
                            <span class="text-xl text-red-600">💰</span>
                            <span class="text-heading-lg text-red-600 dark:text-red-400">
                              {offer.quantity}
                            </span>
                            <span class="text-label-sm text-red-500 dark:text-red-400">
                              {if offer.quantity == 1, do: "card", else: "cards"}
                            </span>
                          <% true -> %>
                            <span class="text-xl text-blue-600">🔄</span>
                            <span class="text-heading-lg text-blue-600 dark:text-blue-400">
                              {offer.quantity}
                            </span>
                            <span class="text-label-sm text-blue-500 dark:text-blue-400">
                              {if offer.quantity == 1, do: "card", else: "cards"}
                            </span>
                        <% end %>
                      </div>
                      <div class="text-right">
                        <div class="text-heading-sm font-semibold text-gray-900 dark:text-white">
                          {format_price(offer.price)}
                        </div>
                        <div class="text-label-xs text-gray-500 dark:text-gray-400">per card</div>
                      </div>
                    </div>
                    <div class="flex items-center justify-between">
                      <div>
                        <div class="text-label-sm text-gray-600 dark:text-gray-400">Total Value</div>
                        <div class="text-heading-xs font-bold text-gray-900 dark:text-white">
                          {format_price(offer.total_value)}
                        </div>
                      </div>
                      <div class="text-right">
                        <div class="text-label-sm text-gray-600 dark:text-gray-400">Status</div>
                        <div class="text-label-sm font-medium text-green-600 dark:text-green-400">
                          ✅ Active
                        </div>
                      </div>
                    </div>
                  </div>
                  <div class="mt-4">
                    <button
                      phx-click="cancel_offer"
                      phx-value-offer_id={offer.id}
                      class="w-full py-3 px-4 bg-red-600 hover:bg-red-700 text-white rounded-lg font-medium text-body-md transition-colors"
                      data-confirm="Are you sure you want to cancel this offer?"
                    >
                      🗑️ Cancel Offer
                    </button>
                  </div>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end