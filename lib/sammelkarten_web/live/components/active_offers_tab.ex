defmodule SammelkartenWeb.TradingLive.ActiveOffersTab do
  import SammelkartenWeb.TradingHelpers, only: [filter_and_sort_offers: 4]
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

  defp format_price(price) when is_integer(price),
    do: Sammelkarten.Formatter.format_german_price(price)

  defp format_price(price) when is_float(price),
    do: Sammelkarten.Formatter.format_german_price(trunc(price))

  use Phoenix.Component

  def active_offers_tab(assigns) do
    ~H"""
    <div>
      <!-- Filters and Search -->
      <div class="flex flex-col sm:flex-row gap-4 mb-6">
        <div class="flex gap-2">
          <button
            phx-click="filter_offers"
            phx-value-type="all"
            class={"px-4 py-2 rounded-lg text-label-md
            transition-colors #{if @filter_type=="all" , do: "bg-primary text-primary-foreground" ,
            else: "bg-card text-text hover:bg-card-hover" }"}
          >
            All
          </button>
          <button
            phx-click="filter_offers"
            phx-value-type="buy"
            class={"px-4 py-2 rounded-lg text-label-md
            transition-colors #{if @filter_type=="buy" , do: "bg-success text-success-foreground" ,
            else: "bg-card text-text hover:bg-card-hover" }"}
          >
            🛒 Buy Orders
          </button>
          <button
            phx-click="filter_offers"
            phx-value-type="sell"
            class={"px-4 py-2 rounded-lg text-label-md
            transition-colors #{if @filter_type=="sell" , do: "bg-destructive text-destructive-foreground" ,
            else: "bg-card text-text hover:bg-card-hover" }"}
          >
            💰 Sell Orders
          </button>
          <button
            phx-click="filter_offers"
            phx-value-type="exchange"
            class={"px-4 py-2 rounded-lg text-label-md
            transition-colors #{if @filter_type=="exchange" , do: "bg-blue-600 text-white" ,
            else: "bg-card text-text hover:bg-card-hover" }"}
          >
            🔄 Exchanges
          </button>
        </div>
        <div class="flex gap-2">
          <button
            phx-click="sort_offers"
            phx-value-by="newest"
            class={"px-4 py-2 rounded-lg text-label-md
            transition-colors #{if @sort_by=="newest" , do: "bg-primary text-primary-foreground" ,
            else: "bg-card text-text hover:bg-card-hover" }"}
          >
            Newest
          </button>
          <button
            phx-click="sort_offers"
            phx-value-by="price_low"
            class={"px-4 py-2 rounded-lg text-label-md
            transition-colors #{if @sort_by=="price_low" , do: "bg-primary text-primary-foreground" ,
            else: "bg-card text-text hover:bg-card-hover" }"}
          >
            Price ↑
          </button>
          <button
            phx-click="sort_offers"
            phx-value-by="price_high"
            class={"px-4 py-2 rounded-lg text-label-md
            transition-colors #{if @sort_by=="price_high" , do: "bg-primary text-primary-foreground" ,
            else: "bg-card text-text hover:bg-card-hover" }"}
          >
            Price ↓
          </button>
        </div>
      </div>
      <!-- Active Offers Grid -->
      <%= if length(filter_and_sort_offers(@active_offers, @search_query, @filter_type, @sort_by))==0 do %>
        <div class="text-center py-12">
          <div class="text-6xl mb-4">🔍</div>
          <h3 class="text-heading-sm text-text mb-2">No Active Offers</h3>
          <p class="text-body-md text-secondary">
            There are no active trade offers at the moment. Check back later or
            create your own offer!
          </p>
        </div>
      <% else %>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
          <%= for offer <- filter_and_sort_offers(@active_offers, @search_query, @filter_type, @sort_by) do %>
            <%= if Map.has_key?(offer, :card) do %>
              <.link
                navigate={"/#{offer.card.slug}"}
                class={"card-grid-item card-professional card-hover block overflow-hidden cursor-pointer " <>
                              (if @current_user && offer.user_pubkey == @current_user.pubkey, do: "border-2 border-primary/50 bg-primary/5", else: "")}
              >
                <!-- Card Image -->
                <div class="aspect-w-3 aspect-h-4 bg-gray-100 dark:bg-gray-700 overflow-hidden">
                  <img
                    src={offer.card.image_path}
                    alt={offer.card.name}
                    class="card-image-hover w-full h-48 object-cover object-top"
                    loading="lazy"
                  />
                </div>
                <!-- Card Content -->
                <div class="p-4">
                  <!-- Card Name and Offer Type -->
                  <div class="flex items-start justify-between mb-4">
                    <h3 class="text-heading-md text-gray-900 dark:text-white truncate flex-1">
                      {offer.card.name}
                    </h3>
                    <span class={"ml-2 px-2.5 py-1 text-label-sm rounded-full shrink-0
                        #{rarity_color(offer.card.rarity)}"}>
                      {offer.card.rarity}
                    </span>
                  </div>
                  <!-- Trading Information -->
                  <div class="space-y-3">
                    <!-- Offer Type and Quantity -->
                    <div class="flex items-center justify-between">
                      <div class="flex items-center space-x-2">
                        <%= cond do %>
                          <% offer.offer_type=="buy" -> %>
                            <span class="text-xl text-green-600">🛒</span>
                            <span class="text-heading-lg text-green-600 dark:text-green-400">
                              {offer.quantity}
                            </span>
                            <span class="text-label-sm text-green-500 dark:text-green-400">
                              <%= if offer.quantity == 1 do %>
                                card
                              <% else %>
                                cards
                              <% end %>
                            </span>
                          <% offer.offer_type=="sell" -> %>
                            <span class="text-xl text-red-600">💰</span>
                            <span class="text-heading-lg text-red-600 dark:text-red-400">
                              {offer.quantity}
                            </span>
                            <span class="text-label-sm text-red-500 dark:text-red-400">
                              <%= if offer.quantity == 1 do %>
                                card
                              <% else %>
                                cards
                              <% end %>
                            </span>
                          <% true -> %>
                            <span class="text-xl text-blue-600">🔄</span>
                            <span class="text-heading-lg text-blue-600 dark:text-blue-400">
                              {offer.quantity}
                            </span>
                            <span class="text-label-sm text-blue-500 dark:text-blue-400">
                              <%= if offer.quantity == 1 do %>
                                card
                              <% else %>
                                cards
                              <% end %>
                            </span>
                        <% end %>
                      </div>
                      <!-- Price per card or Exchange info -->
                      <div class="text-right">
                        <%= if offer.offer_type == "exchange" do %>
                          <div class="text-heading-sm font-semibold text-blue-600 dark:text-blue-400">
                            🔄 Exchange
                          </div>
                          <div class="text-label-xs text-gray-500 dark:text-gray-400">
                            <%= if Map.has_key?(offer, :wanted_type) and offer.wanted_type == "open" do %>
                              for any card
                            <% else %>
                              for specific card
                            <% end %>
                          </div>
                        <% else %>
                          <div class="text-heading-sm font-semibold text-gray-900 dark:text-white">
                            {format_price(offer.price)}
                          </div>
                          <div class="text-label-xs text-gray-500 dark:text-gray-400">per card</div>
                        <% end %>
                      </div>
                    </div>
                    <!-- Total Value and Trader Info -->
                    <div class="flex items-center justify-between">
                      <div>
                        <%= if offer.offer_type == "exchange" do %>
                          <div class="text-label-sm text-gray-600 dark:text-gray-400">Exchange</div>
                          <div class="text-heading-xs font-bold text-blue-600 dark:text-blue-400">
                            No Money
                          </div>
                        <% else %>
                          <div class="text-label-sm text-gray-600 dark:text-gray-400">Total</div>
                          <div class="text-heading-xs font-bold text-gray-900 dark:text-white">
                            {format_price(offer.total_value)}
                          </div>
                        <% end %>
                      </div>
                      <div class="text-right">
                        <div class="text-label-sm text-gray-600 dark:text-gray-400">Trader</div>
                        <div class="text-label-sm font-mono text-gray-900 dark:text-white">
                          {offer.user_short}
                        </div>
                      </div>
                    </div>
                  </div>
                  <!-- Action -->
                  <div class="mt-4">
                    <%= if @authenticated and @current_user &&
                        offer.user_pubkey==@current_user.pubkey do %>
                      <div class="w-full py-3 px-4 bg-gray-100 dark:bg-gray-700 rounded-lg text-center text-gray-500 dark:text-gray-400 text-body-md">
                        🚫 Cannot trade with yourself
                      </div>
                    <% else %>
                      <%= if @authenticated do %>
                        <button
                          phx-click="accept_offer"
                          phx-value-offer_id={offer.id}
                          class={"w-full py-3 px-4 rounded-lg font-medium text-body-md transition-colors " <>
                                                          (cond do
                                                            offer.offer_type == "buy" -> "bg-green-600 hover:bg-green-700 text-white"
                                                            offer.offer_type == "sell" -> "bg-red-600 hover:bg-red-700 text-white"
                                                            true -> "bg-blue-600 hover:bg-blue-700 text-white"
                                                          end)}
                        >
                          <%= cond do %>
                            <% offer.offer_type=="buy" -> %>
                              💰 Sell to This Buyer
                            <% offer.offer_type=="sell" -> %>
                              🛒 Buy from This
                              Seller
                            <% true -> %>
                              🔄 Accept Exchange
                          <% end %>
                        </button>
                      <% else %>
                        <div class="w-full py-3 px-4 bg-gray-300 dark:bg-gray-600 rounded-lg text-center text-gray-500 dark:text-gray-400 text-body-md cursor-not-allowed opacity-60">
                          <%= cond do %>
                            <% offer.offer_type=="buy" -> %>
                              💰 Sell to This
                              Buyer
                            <% offer.offer_type=="sell" -> %>
                              🛒 Buy from
                              This Seller
                            <% true -> %>
                              🔄 Accept Exchange
                          <% end %>
                        </div>
                      <% end %>
                    <% end %>
                  </div>
                </div>
              </.link>
            <% else %>
              <div class={"card-grid-item card-professional card-hover block overflow-hidden " <>
                              (if @current_user && offer.user_pubkey == @current_user.pubkey, do: "border-2 border-primary/50 bg-primary/5", else: "cursor-pointer")}>
                <div class="w-full h-48 bg-muted flex items-center justify-center">
                  <div class="text-6xl text-muted-foreground">?</div>
                </div>
                <!-- Card Content -->
                <div class="p-4">
                  <!-- Card Name and Offer Type -->
                  <div class="flex items-start justify-between mb-4">
                    <h3 class="text-heading-md text-gray-900 dark:text-white truncate flex-1">
                      Unknown Card
                    </h3>
                  </div>
                  <!-- Trading Information -->
                  <div class="space-y-3">
                    <!-- Offer Type and Quantity -->
                    <div class="flex items-center justify-between">
                      <div class="flex items-center space-x-2">
                        <%= cond do %>
                          <% offer.offer_type=="buy" -> %>
                            <span class="text-xl text-green-600">🛒</span>
                            <span class="text-heading-lg text-green-600 dark:text-green-400">
                              {offer.quantity}
                            </span>
                            <span class="text-label-sm text-green-500 dark:text-green-400">
                              <%= if offer.quantity == 1 do %>
                                card
                              <% else %>
                                cards
                              <% end %>
                            </span>
                          <% offer.offer_type=="sell" -> %>
                            <span class="text-xl text-red-600">💰</span>
                            <span class="text-heading-lg text-red-600 dark:text-red-400">
                              {offer.quantity}
                            </span>
                            <span class="text-label-sm text-red-500 dark:text-red-400">
                              <%= if offer.quantity == 1 do %>
                                card
                              <% else %>
                                cards
                              <% end %>
                            </span>
                          <% true -> %>
                            <span class="text-xl text-blue-600">🔄</span>
                            <span class="text-heading-lg text-blue-600 dark:text-blue-400">
                              {offer.quantity}
                            </span>
                            <span class="text-label-sm text-blue-500 dark:text-blue-400">
                              <%= if offer.quantity == 1 do %>
                                card
                              <% else %>
                                cards
                              <% end %>
                            </span>
                        <% end %>
                      </div>
                      <!-- Price per card or Exchange info -->
                      <div class="text-right">
                        <%= if offer.offer_type == "exchange" do %>
                          <div class="text-heading-sm font-semibold text-blue-600 dark:text-blue-400">
                            🔄 Exchange
                          </div>
                          <div class="text-label-xs text-gray-500 dark:text-gray-400">
                            <%= if Map.has_key?(offer, :wanted_type) and offer.wanted_type == "open" do %>
                              for any card
                            <% else %>
                              for specific card
                            <% end %>
                          </div>
                        <% else %>
                          <div class="text-heading-sm font-semibold text-gray-900 dark:text-white">
                            {format_price(offer.price)}
                          </div>
                          <div class="text-label-xs text-gray-500 dark:text-gray-400">per card</div>
                        <% end %>
                      </div>
                    </div>
                    <!-- Total Value and Trader Info -->
                    <div class="flex items-center justify-between">
                      <div>
                        <%= if offer.offer_type == "exchange" do %>
                          <div class="text-label-sm text-gray-600 dark:text-gray-400">Exchange</div>
                          <div class="text-heading-xs font-bold text-blue-600 dark:text-blue-400">
                            No Money
                          </div>
                        <% else %>
                          <div class="text-label-sm text-gray-600 dark:text-gray-400">Total</div>
                          <div class="text-heading-xs font-bold text-gray-900 dark:text-white">
                            {format_price(offer.total_value)}
                          </div>
                        <% end %>
                      </div>
                      <div class="text-right">
                        <div class="text-label-sm text-gray-600 dark:text-gray-400">Trader</div>
                        <div class="text-label-sm font-mono text-gray-900 dark:text-white">
                          {offer.user_short}
                        </div>
                      </div>
                    </div>
                  </div>
                  <!-- Action -->
                  <div class="mt-4">
                    <%= if @authenticated and @current_user &&
                        offer.user_pubkey==@current_user.pubkey do %>
                      <div class="w-full py-3 px-4 bg-gray-100 dark:bg-gray-700 rounded-lg text-center text-gray-500 dark:text-gray-400 text-body-md">
                        🚫 Cannot trade with yourself
                      </div>
                    <% else %>
                      <%= if @authenticated do %>
                        <button
                          phx-click="accept_offer"
                          phx-value-offer_id={offer.id}
                          class={"w-full py-3 px-4 rounded-lg font-medium text-body-md transition-colors " <>
                                                          (cond do
                                                            offer.offer_type == "buy" -> "bg-green-600 hover:bg-green-700 text-white"
                                                            offer.offer_type == "sell" -> "bg-red-600 hover:bg-red-700 text-white"
                                                            true -> "bg-blue-600 hover:bg-blue-700 text-white"
                                                          end)}
                        >
                          <%= cond do %>
                            <% offer.offer_type=="buy" -> %>
                              💰 Sell to This Buyer
                            <% offer.offer_type=="sell" -> %>
                              🛒 Buy from This
                              Seller
                            <% true -> %>
                              🔄 Accept Exchange
                          <% end %>
                        </button>
                      <% else %>
                        <div class="w-full py-3 px-4 bg-gray-300 dark:bg-gray-600 rounded-lg text-center text-gray-500 dark:text-gray-400 text-body-md cursor-not-allowed opacity-60">
                          <%= cond do %>
                            <% offer.offer_type=="buy" -> %>
                              💰 Sell to This
                              Buyer
                            <% offer.offer_type=="sell" -> %>
                              🛒 Buy from
                              This Seller
                            <% true -> %>
                              🔄 Accept Exchange
                          <% end %>
                        </div>
                      <% end %>
                    <% end %>
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