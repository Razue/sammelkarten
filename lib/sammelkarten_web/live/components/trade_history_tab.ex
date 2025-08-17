defmodule SammelkartenWeb.TradingLive.TradeHistoryTab do
  use Phoenix.Component

  def trade_history_tab(assigns) do
    ~H"""
    <div>
      <%= if length(@trade_history)==0 do %>
        <div class="text-center py-12">
          <div class="text-6xl mb-4">📈</div>
          <h3 class="text-heading-sm text-text mb-2">No Trade History</h3>
          <p class="text-body-md text-secondary">
            You haven't completed any trades yet. Start trading to build your
            history!
          </p>
        </div>
      <% else %>
        <div class="space-y-4">
          <%= for trade <- @trade_history do %>
            <div class="card-professional p-6">
              <div class="flex items-center justify-between mb-4">
                <div class="flex items-center gap-3">
                  <%= if Map.has_key?(trade, :card) do %>
                    <img
                      src={trade.card.image_path}
                      alt={trade.card.name}
                      class="w-10 h-10 object-cover rounded-lg"
                    />
                    <div>
                      <h4 class="text-body-md font-medium text-text">{trade.card.name}</h4>
                      <div class="text-label-sm text-secondary">
                        {trade.quantity} card(s) • {format_price(trade.price)} each
                      </div>
                    </div>
                  <% end %>
                </div>
                <div class="text-right">
                  <div class="text-heading-xs font-semibold text-text">
                    {format_price(trade.total_value)}
                  </div>
                  <div class="text-label-sm text-secondary">
                    {format_datetime(trade.completed_at)}
                  </div>
                </div>
              </div>
              <div class="flex items-center justify-between text-label-sm text-secondary">
                <div>Seller: <span class="font-mono">{trade.seller_short}</span></div>
                <div>➡️</div>
                <div>Buyer: <span class="font-mono">{trade.buyer_short}</span></div>
              </div>
              <%= if @current_user && trade.seller_pubkey==@current_user.pubkey do %>
                <div class="mt-2 inline-flex items-center px-2 py-1 rounded-full bg-success/20 text-success text-label-xs">
                  💰 Sold
                </div>
              <% else %>
                <div class="mt-2 inline-flex items-center px-2 py-1 rounded-full bg-primary/20 text-primary text-label-xs">
                  🛒 Bought
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # Private helper functions for formatting
  defp format_price(price) when is_integer(price),
    do: Sammelkarten.Formatter.format_german_price(price)

  defp format_price(price) when is_float(price),
    do: Sammelkarten.Formatter.format_german_price(trunc(price))

  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%d.%m.%Y %H:%M")
  defp format_datetime(dt) when is_binary(dt), do: dt
end
