defmodule SammelkartenWeb.TradingLive.CreateOfferTab do
  use Phoenix.Component

  def create_offer_tab(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto">
      <%= if not @show_create_form do %>
        <div class="card-professional p-8 text-center">
          <div class="text-4xl mb-4">➕</div>
          <h2 class="text-heading-md font-semibold text-text mb-4">Create New Trade Offer</h2>
          <p class="text-body-md text-secondary mb-6">
            Create a buy or sell order for other users to discover and trade with you.
          </p>
          <button type="button" phx-click="show_create_form" class="btn-primary px-6 py-3">
            📝 Start Creating Offer
          </button>
        </div>
      <% else %>
        <div class="card-professional p-8">
          <div class="flex items-center justify-between mb-6">
            <h2 class="text-heading-md font-semibold text-text">➕ Create New Trade Offer</h2>
            <button
              type="button"
              phx-click="hide_create_form"
              class="text-secondary hover:text-text text-2xl"
            >
              ✕
            </button>
          </div>
          <form phx-submit="create_offer" phx-change="update_form" class="space-y-6">
            <div>
              <label class="block text-label-md font-medium text-text mb-2">
                Select Card <span class="text-destructive">*</span>
              </label>
              <select
                name="card_id"
                value={@offer_form["card_id"]}
                required
                class="input-professional w-full"
              >
                <option value="">Choose a card...</option>
                <%= for card <- @available_cards do %>
                  <option value={card.id} selected={@offer_form["card_id"] == card.id}>
                    {card.name} ({String.capitalize(card.rarity)})
                  </option>
                <% end %>
              </select>
            </div>
            <div>
              <label class="block text-label-md font-medium text-text mb-2">
                Offer Type <span class="text-destructive">*</span>
              </label>
              <div class="grid grid-cols-3 gap-3">
                <button
                  type="button"
                  phx-click="select_offer_type"
                  phx-value-type="buy"
                  class={"w-full rounded-lg border-2 p-4 text-center transition-all duration-200 #{if @selected_offer_type == "buy", do: "border-success bg-success/10 shadow-md", else: "border-border hover:border-success hover:bg-card-hover"}"}
                >
                  <div class="text-2xl mb-2">🛒</div>
                  <div class="text-body-md font-medium text-text">Buy Order</div>
                  <div class="text-label-sm text-secondary">I want to buy</div>
                  <%= if @selected_offer_type == "buy" do %>
                    <div class="mt-2 text-success text-label-sm font-medium">✓ Selected</div>
                  <% end %>
                </button>
                <button
                  type="button"
                  phx-click="select_offer_type"
                  phx-value-type="sell"
                  class={"w-full rounded-lg border-2 p-4 text-center transition-all duration-200 #{if @selected_offer_type == "sell", do: "border-destructive bg-destructive/10 shadow-md", else: "border-border hover:border-destructive hover:bg-card-hover"}"}
                >
                  <div class="text-2xl mb-2">💰</div>
                  <div class="text-body-md font-medium text-text">Sell Order</div>
                  <div class="text-label-sm text-secondary">I want to sell</div>
                  <%= if @selected_offer_type == "sell" do %>
                    <div class="mt-2 text-destructive text-label-sm font-medium">✓ Selected</div>
                  <% end %>
                </button>
                <button
                  type="button"
                  phx-click="select_offer_type"
                  phx-value-type="exchange"
                  class={"w-full rounded-lg border-2 p-4 text-center transition-all duration-200 #{if @selected_offer_type == "exchange", do: "border-primary bg-primary/10 shadow-md", else: "border-border hover:border-primary hover:bg-card-hover"}"}
                >
                  <div class="text-2xl mb-2">🔄</div>
                  <div class="text-body-md font-medium text-text">Exchange</div>
                  <div class="text-label-sm text-secondary">Card for card</div>
                  <%= if @selected_offer_type == "exchange" do %>
                    <div class="mt-2 text-primary text-label-sm font-medium">✓ Selected</div>
                  <% end %>
                </button>
              </div>
              <%= if @selected_offer_type do %>
                <div class={"mt-3 p-3 rounded-lg #{if @selected_offer_type == "exchange", do: "bg-primary/5 border border-primary/20", else: "bg-success/5 border border-success/20"}"}>
                  <div class={"flex items-center gap-2 text-label-sm #{if @selected_offer_type == "exchange", do: "text-primary", else: "text-success"}"}>
                    <div class={"w-2 h-2 rounded-full #{if @selected_offer_type == "exchange", do: "bg-primary", else: "bg-success"}"}>
                    </div>
                    <%= if @selected_offer_type == "buy" do %>
                      You're creating a <strong>Buy Order</strong>
                      - other users can sell their cards to you
                    <% else %>
                      <%= if @selected_offer_type == "sell" do %>
                        You're creating a <strong>Sell Order</strong>
                        - other users can buy cards from you
                      <% else %>
                        You're creating an <strong>Exchange Offer</strong>
                        - other users can trade cards directly with you (no money involved)
                      <% end %>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-label-md font-medium text-text mb-2">
                  Price per Card (sats) <span class="text-destructive">*</span>
                </label>
                <input
                  type="number"
                  name="price"
                  value={@offer_form["price"]}
                  step="1"
                  min="1"
                  placeholder="100"
                  required
                  class="input-professional w-full"
                />
              </div>
              <div>
                <label class="block text-label-md font-medium text-text mb-2">
                  Quantity <span class="text-destructive">*</span>
                </label>
                <input
                  type="number"
                  name="quantity"
                  value={@offer_form["quantity"]}
                  min="1"
                  placeholder="1"
                  required
                  class="input-professional w-full"
                />
              </div>
            </div>
            <div class="bg-muted/50 rounded-lg p-4">
              <h4 class="text-body-md font-medium text-text mb-2">📋 Trading Terms</h4>
              <ul class="text-label-md text-secondary space-y-1">
                <li>• All trades are peer-to-peer via Nostr events</li>
                <li>• No fees - direct trader-to-trader exchange</li>
                <li>• Trades are recorded permanently on Nostr relays</li>
              </ul>
            </div>
            <button type="submit" class="w-full btn-primary py-4 text-body-md font-medium">
              🚀 Create Trade Offer
            </button>
          </form>
        </div>
      <% end %>
    </div>
    """
  end
end
