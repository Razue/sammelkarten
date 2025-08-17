defmodule SammelkartenWeb.TradingLive.ExchangesTab do
  use Phoenix.Component

  def exchanges_tab(assigns) do
    ~H"""
    <div>
      <!-- Create Exchange Button -->
      <div class="mb-6">
        <button phx-click="show_exchange_form" class="btn-primary">➕ Create New Exchange</button>
      </div>
      <!-- Exchange Form -->
      <%= if @show_exchange_form do %>
        <div class="card-professional p-6 mb-6">
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-heading-md font-semibold text-text">🔄 Create Card Exchange</h3>
            <button
              type="button"
              phx-click="hide_exchange_form"
              class="text-secondary hover:text-text text-2xl"
            >
              ✕
            </button>
          </div>
          <form phx-submit="create_exchange" phx-change="update_exchange_form" class="space-y-4">
            <!-- Card I'm Offering -->
            <div>
              <label class="block text-label-md font-medium text-text mb-2">
                Card I'm Offering <span class="text-destructive">*</span>
              </label>
              <select
                name="offering_card_id"
                value={@exchange_form["offering_card_id"]}
                required
                class="input-professional w-full"
              >
                <option value="">Choose a card to offer...</option>
                <%= for card <- @portfolio_cards do %>
                  <option value={card.id} selected={@exchange_form["offering_card_id"] == card.id}>
                    {card.name} ({String.capitalize(card.rarity)})
                  </option>
                <% end %>
              </select>
            </div>
            <!-- Want Type Selection -->
            <div>
              <label class="block text-label-md font-medium text-text mb-2">
                What I Want <span class="text-destructive">*</span>
              </label>
              <div class="space-y-3">
                <label class="flex items-center">
                  <input
                    type="radio"
                    name="wanted_type"
                    value="open"
                    checked={@exchange_form["wanted_type"] == "open"}
                    class="mr-2 text-primary"
                  />
                  <span class="text-body-md">🌟 Open to any card (maximum flexibility)</span>
                </label>
                <label class="flex items-center">
                  <input
                    type="radio"
                    name="wanted_type"
                    value="specific"
                    checked={@exchange_form["wanted_type"] == "specific"}
                    class="mr-2 text-primary"
                  />
                  <span class="text-body-md">🎯 Specific cards I want</span>
                </label>
              </div>
            </div>
            <!-- Specific Cards Selection (shown when specific type is selected) -->
            <%= if @exchange_form["wanted_type"]=="specific" do %>
              <div>
                <label class="block text-label-md font-medium text-text mb-2">
                  Cards I Want <span class="text-destructive">*</span>
                </label>
                <div class="grid grid-cols-2 gap-2 max-h-60 overflow-y-auto border border-border rounded-lg p-2">
                  <%= for card <- @available_cards do %>
                    <label class="flex items-center p-2 hover:bg-muted rounded">
                      <input
                        type="checkbox"
                        name="wanted_card_ids[]"
                        value={card.id}
                        checked={card.id in (@exchange_form["wanted_card_ids"] || [])}
                        class="mr-2 text-primary"
                      />
                      <span class="text-body-sm">{card.name} ({String.capitalize(card.rarity)})</span>
                    </label>
                  <% end %>
                </div>
              </div>
            <% end %>
            <!-- Quantity -->
            <div>
              <label class="block text-label-md font-medium text-text mb-2">
                Quantity <span class="text-destructive">*</span>
              </label>
              <input
                type="number"
                name="quantity"
                value={@exchange_form["quantity"]}
                min="1"
                placeholder="1"
                required
                class="input-professional w-full"
              />
            </div>
            <!-- Submit Button -->
            <button type="submit" class="w-full btn-primary py-3 text-body-md font-medium">🔄 Create
              Exchange Offer</button>
          </form>
        </div>
      <% end %>
      <!-- Exchange Offers -->
      <%= if length(@exchange_offers)==0 do %>
        <div class="text-center py-12">
          <div class="text-6xl mb-4">🔄</div>
          <h3 class="text-heading-sm text-text mb-2">No Exchange Offers</h3>
          <p class="text-body-md text-secondary">
            No card-for-card exchange offers available yet. Create one to
            start exchanging cards without money!
          </p>
        </div>
      <% else %>
        <div class="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-3 gap-6">
          <%= for exchange <- @exchange_offers do %>
            <div class="card-professional p-6">
              <.link
                navigate={"/#{exchange.offering_card.slug}"}
                class="block hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors duration-200 cursor-pointer rounded p-2 -m-2 mb-2"
              >
                <div class="flex items-center gap-2 mb-4">
                  <span class="text-label-sm text-secondary">Trader:</span>
                  <span class="text-label-sm font-mono text-text">{exchange.user_short}</span>
                </div>
                <!-- Exchange Details -->
                <div class="flex items-center gap-4 mb-4">
                  <!-- Offering Card -->
                  <div class="flex-1 text-center">
                    <div class="w-16 h-20 mx-auto mb-2 bg-gray-100 dark:bg-gray-700 rounded overflow-hidden">
                      <img
                        src={exchange.offering_card.image_path}
                        alt={exchange.offering_card.name}
                        class="w-full h-full object-cover"
                        loading="lazy"
                      />
                    </div>
                    <h4 class="text-label-sm font-medium text-text truncate">
                      {exchange.offering_card.name}
                    </h4>
                    <div class="text-label-xs text-secondary">Offering x{exchange.quantity}</div>
                  </div>
                  <!-- Exchange Symbol -->
                  <div class="text-2xl text-primary">🔄</div>
                  <!-- Wanted Card(s) -->
                  <div class="flex-1 text-center">
                    <%= if exchange.wanted_type=="open" do %>
                      <div class="w-16 h-20 mx-auto mb-2 bg-gradient-to-br from-blue-100 to-purple-100 dark:from-blue-900/30 dark:to-purple-900/30 rounded overflow-hidden flex items-center justify-center">
                        <span class="text-2xl">🌟</span>
                      </div>
                      <h4 class="text-label-sm font-medium text-text">Any Card</h4>
                      <div class="text-label-xs text-secondary">Open to offers</div>
                    <% else %>
                      <%= if length(exchange.wanted_cards)==1 do %>
                        <% card = hd(exchange.wanted_cards) %>
                        <div class="w-16 h-20 mx-auto mb-2 bg-gray-100 dark:bg-gray-700 rounded overflow-hidden">
                          <img
                            src={card.image_path}
                            alt={card.name}
                            class="w-full h-full object-cover"
                            loading="lazy"
                          />
                        </div>
                        <h4 class="text-label-sm font-medium text-text truncate">
                          {card.name}
                        </h4>
                        <div class="text-label-xs text-secondary">Wants this card</div>
                      <% else %>
                        <div class="w-16 h-20 mx-auto mb-2 bg-gradient-to-br from-green-100 to-blue-100 dark:from-green-900/30 dark:to-blue-900/30 rounded overflow-hidden flex items-center justify-center">
                          <span class="text-xl">🎯</span>
                        </div>
                        <h4 class="text-label-sm font-medium text-text">
                          {length(exchange.wanted_cards)} Options
                        </h4>
                        <div class="text-label-xs text-secondary">Multiple
                          choices</div>
                      <% end %>
                    <% end %>
                  </div>
                </div>
              </.link>
              <!-- Action -->
              <%= if @authenticated and @current_user && exchange.user_pubkey==@current_user.pubkey do %>
                <button
                  phx-click="cancel_offer"
                  phx-value-offer_id={exchange.id}
                  class="w-full py-2 px-4 bg-red-600 hover:bg-red-700 text-white rounded-lg text-label-md transition-colors"
                  data-confirm="Are you sure you want to cancel this exchange?"
                >
                  🗑️
                  Cancel
                </button>
              <% else %>
                <%= if @authenticated do %>
                  <button
                    phx-click="accept_offer"
                    phx-value-offer_id={exchange.id}
                    class="w-full py-2 px-4 bg-blue-600 hover:bg-blue-700 text-white rounded-lg text-label-md transition-colors"
                  >
                    🤝
                    Accept Exchange
                  </button>
                <% else %>
                  <div class="w-full py-2 px-4 bg-gray-300 dark:bg-gray-600 rounded-lg text-center text-gray-500 dark:text-gray-400 text-label-md cursor-not-allowed opacity-60">
                    🤝 Accept Exchange
                  </div>
                <% end %>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
