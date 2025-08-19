defmodule Sammelkarten.Nostr.Indexer do
  @moduledoc """
  GenServer that indexes Nostr events for Sammelkarten.
  Maintains ETS tables for cards, offers, executions, collections, and portfolios.
  Subscribes to relay feeds and rebuilds state from event logs.
  """

  use GenServer
  alias Sammelkarten.Nostr.Event
  alias Phoenix.PubSub

  require Logger

  @card_definition 32121
  @user_collection 32122
  @trade_offer 32123
  @trade_execution 32124
  # @price_alert 32125
  @portfolio_snapshot 32126
  @trade_cancel 32127

  # ETS table names
  @cards_table :nostr_cards
  @offers_table :nostr_offers
  @executions_table :nostr_executions
  @collections_table :nostr_collections
  @portfolio_table :nostr_portfolios
  @alerts_table :nostr_alerts

  defstruct [
    :cards_table,
    :offers_table,
    :executions_table,
    :collections_table,
    :portfolios_table,
    :alerts_table,
    latest_timestamp: 0
  ]

  @type t :: %__MODULE__{
          cards_table: atom(),
          offers_table: atom(),
          executions_table: atom(),
          collections_table: atom(),
          portfolios_table: atom(),
          alerts_table: atom(),
          latest_timestamp: integer()
        }

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get current indexer state.
  """
  def state do
    GenServer.call(__MODULE__, :state)
  end

  @doc """
  Fetch a card definition by card_id.
  """
  def fetch_card(card_id) do
    case :ets.lookup(@cards_table, card_id) do
      [{^card_id, card_data}] -> {:ok, card_data}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Fetch an offer by event ID.
  """
  def fetch_offer(event_id) do
    case :ets.lookup(@offers_table, event_id) do
      [{^event_id, offer_data}] -> {:ok, offer_data}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  List all cards.
  """
  def list_cards do
    :ets.tab2list(@cards_table)
    |> Enum.map(fn {_card_id, card_data} -> card_data end)
  end

  @doc """
  List all open offers.
  """
  def list_open_offers do
    :ets.tab2list(@offers_table)
    |> Enum.map(fn {_event_id, offer_data} -> offer_data end)
    |> Enum.filter(fn offer -> offer.status == :open end)
  end

  @doc """
  List all executions.
  """
  def list_executions do
    :ets.tab2list(@executions_table)
    |> Enum.map(fn {_event_id, execution_data} -> execution_data end)
  end

  @doc """
  List all portfolios.
  """
  def list_portfolios do
    :ets.tab2list(@portfolio_table)
    |> Enum.map(fn {_pubkey, portfolio_data} -> portfolio_data end)
  end

  @doc """
  Fetch user collection by pubkey.
  """
  def fetch_user_collection(pubkey) do
    case :ets.lookup(@collections_table, pubkey) do
      [{^pubkey, collection_data}] -> {:ok, collection_data}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  List all user collections.
  """
  def list_user_collections do
    :ets.tab2list(@collections_table)
    |> Enum.map(fn {_pubkey, collection_data} -> collection_data end)
  end

  @doc """
  Get a portfolio snapshot by pubkey.
  """
  def get_portfolio(pubkey) do
    case :ets.lookup(@portfolio_table, pubkey) do
      [{^pubkey, portfolio_data}] -> {:ok, portfolio_data}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Fetch execution by event ID.
  """
  def fetch_execution(event_id) do
    case :ets.lookup(@executions_table, event_id) do
      [{^event_id, execution_data}] -> {:ok, execution_data}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  List offers by status.
  """
  def list_offers_by_status(status) do
    :ets.tab2list(@offers_table)
    |> Enum.map(fn {_event_id, offer_data} -> offer_data end)
    |> Enum.filter(fn offer -> offer.status == status end)
  end

  @doc """
  List executions for a specific offer.
  """
  def list_executions_for_offer(offer_id) do
    :ets.tab2list(@executions_table)
    |> Enum.map(fn {_event_id, execution_data} -> execution_data end)
    |> Enum.filter(fn execution -> execution.offer_id == offer_id end)
  end

  @doc """
  Index a single event (used for real-time updates).
  """
  def index_event(%Event{} = event) do
    GenServer.cast(__MODULE__, {:index_event, event})
  end

  @doc """
  Rebuild all indexes from event history.
  """
  def rebuild do
    GenServer.call(__MODULE__, :rebuild, 30_000)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      cards_table: create_table(@cards_table),
      offers_table: create_table(@offers_table),
      executions_table: create_table(@executions_table),
      collections_table: create_table(@collections_table),
      portfolios_table: create_table(@portfolio_table),
      alerts_table: create_table(@alerts_table),
      latest_timestamp: 0
    }

    Logger.info("Nostr Indexer started with ETS tables")
    {:ok, state}
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:rebuild, _from, state) do
    Logger.info("Rebuilding Nostr indexes...")

    # Clear all tables
    :ets.delete_all_objects(@cards_table)
    :ets.delete_all_objects(@offers_table)
    :ets.delete_all_objects(@executions_table)
    :ets.delete_all_objects(@collections_table)
    :ets.delete_all_objects(@portfolio_table)
    :ets.delete_all_objects(@alerts_table)

    # TODO: In Phase 10, fetch events from relays and rebuild
    # For now, return empty state
    new_state = %{state | latest_timestamp: DateTime.utc_now() |> DateTime.to_unix()}

    Logger.info("Nostr indexes rebuilt")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast({:index_event, event}, state) do
    new_state = process_event(event, state)
    {:noreply, new_state}
  end

  ## Private Functions

  defp create_table(name) do
    :ets.new(name, [:named_table, :public, :set, {:read_concurrency, true}])
    name
  end

  defp process_event(%Event{kind: @card_definition} = event, state) do
    card_id = Event.get_tag_value(event, "d") |> extract_card_id()

    if card_id do
      # Parse card data from content and tags
      card_data = %{
        card_id: card_id,
        name: Event.get_tag_value(event, "name"),
        rarity: Event.get_tag_value(event, "rarity"),
        set: Event.get_tag_value(event, "set"),
        slug: Event.get_tag_value(event, "slug"),
        image: Event.get_tag_value(event, "image"),
        content: decode_json_content(event.content),
        event_id: event.id,
        created_at: event.created_at,
        pubkey: event.pubkey
      }

      :ets.insert(@cards_table, {card_id, card_data})

      # Broadcast update
      PubSub.broadcast(Sammelkarten.PubSub, "nostr:cards", {:card_updated, card_data})

      Logger.debug("Indexed card definition: #{card_id}")
    end

    %{state | latest_timestamp: max(state.latest_timestamp, event.created_at)}
  end

  defp process_event(%Event{kind: @trade_offer} = event, state) do
    offer_data = %{
      event_id: event.id,
      pubkey: event.pubkey,
      created_at: event.created_at,
      card_id: Event.get_tag_value(event, "card"),
      offer_type: Event.get_tag_value(event, "type"),
      price: Event.get_tag_value(event, "price") |> safe_to_integer(),
      quantity: Event.get_tag_value(event, "quantity") |> safe_to_integer(),
      expires_at: Event.get_tag_value(event, "expires_at") |> safe_to_integer(),
      exchange_card: Event.get_tag_value(event, "exchange_card"),
      content: event.content,
      status: :open
    }

    :ets.insert(@offers_table, {event.id, offer_data})

    # Broadcast update
    PubSub.broadcast(Sammelkarten.PubSub, "nostr:offers", {:offer_created, offer_data})

    Logger.debug("Indexed trade offer: #{event.id}")
    %{state | latest_timestamp: max(state.latest_timestamp, event.created_at)}
  end

  defp process_event(%Event{kind: @trade_execution} = event, state) do
    offer_id = Event.get_tag_values(event, "e") |> List.first()

    # Update offer status to executed
    case :ets.lookup(@offers_table, offer_id) do
      [{^offer_id, offer_data}] ->
        updated_offer = %{offer_data | status: :executed}
        :ets.insert(@offers_table, {offer_id, updated_offer})

        # Broadcast offer update
        PubSub.broadcast(Sammelkarten.PubSub, "nostr:offers", {:offer_executed, updated_offer})

      [] ->
        Logger.warning("Execution references unknown offer: #{offer_id}")
    end

    execution_data = %{
      event_id: event.id,
      pubkey: event.pubkey,
      created_at: event.created_at,
      offer_id: offer_id,
      card_id: Event.get_tag_value(event, "card"),
      quantity: Event.get_tag_value(event, "quantity") |> safe_to_integer(),
      price: Event.get_tag_value(event, "price") |> safe_to_integer(),
      content: event.content
    }

    :ets.insert(@executions_table, {event.id, execution_data})

    # Broadcast execution
    PubSub.broadcast(
      Sammelkarten.PubSub,
      "nostr:executions",
      {:execution_created, execution_data}
    )

    Logger.debug("Indexed trade execution: #{event.id}")
    %{state | latest_timestamp: max(state.latest_timestamp, event.created_at)}
  end

  defp process_event(%Event{kind: @user_collection} = event, state) do
    # Extract discriminator from d tag: collection:<pubkey_or_id>
    discriminator = Event.get_tag_value(event, "d") |> extract_collection_discriminator()

    if discriminator do
      collection_data = %{
        pubkey: event.pubkey,
        discriminator: discriminator,
        cards: decode_json_content(event.content),
        event_id: event.id,
        created_at: event.created_at,
        updated_at: DateTime.utc_now() |> DateTime.to_unix()
      }

      # Store by pubkey for easy lookup
      :ets.insert(@collections_table, {event.pubkey, collection_data})

      # Broadcast update
      PubSub.broadcast(
        Sammelkarten.PubSub,
        "nostr:collections",
        {:collection_updated, collection_data}
      )

      Logger.debug("Indexed user collection: #{event.pubkey} (#{discriminator})")
    else
      Logger.warning("Invalid collection event: missing or invalid d tag")
    end

    %{state | latest_timestamp: max(state.latest_timestamp, event.created_at)}
  end

  defp process_event(%Event{kind: @portfolio_snapshot} = event, state) do
    # Extract discriminator from d tag: portfolio:<pubkey_or_id>
    discriminator = Event.get_tag_value(event, "d") |> extract_portfolio_discriminator()

    if discriminator do
      portfolio_data = %{
        pubkey: event.pubkey,
        discriminator: discriminator,
        data: decode_json_content(event.content),
        event_id: event.id,
        created_at: event.created_at,
        updated_at: DateTime.utc_now() |> DateTime.to_unix()
      }

      # Store by pubkey for easy lookup
      :ets.insert(@portfolio_table, {event.pubkey, portfolio_data})

      # Broadcast update
      PubSub.broadcast(
        Sammelkarten.PubSub,
        "nostr:portfolios",
        {:portfolio_updated, portfolio_data}
      )

      Logger.debug("Indexed portfolio snapshot: #{event.pubkey} (#{discriminator})")
    else
      Logger.warning("Invalid portfolio event: missing or invalid d tag")
    end

    %{state | latest_timestamp: max(state.latest_timestamp, event.created_at)}
  end

  defp process_event(%Event{kind: @trade_cancel} = event, state) do
    offer_id = Event.get_tag_values(event, "e") |> List.first()

    # Update offer status to cancelled
    case :ets.lookup(@offers_table, offer_id) do
      [{^offer_id, offer_data}] ->
        updated_offer = %{offer_data | status: :cancelled}
        :ets.insert(@offers_table, {offer_id, updated_offer})

        # Broadcast cancellation
        PubSub.broadcast(Sammelkarten.PubSub, "nostr:offers", {:offer_cancelled, updated_offer})

      [] ->
        Logger.warning("Cancel references unknown offer: #{offer_id}")
    end

    Logger.debug("Indexed trade cancel for offer: #{offer_id}")
    %{state | latest_timestamp: max(state.latest_timestamp, event.created_at)}
  end

  defp process_event(_event, state) do
    # Ignore other event kinds for now
    state
  end

  defp extract_card_id("card:" <> card_id), do: card_id
  defp extract_card_id(_), do: nil

  defp extract_collection_discriminator("collection:" <> discriminator), do: discriminator
  defp extract_collection_discriminator(_), do: nil

  defp extract_portfolio_discriminator("portfolio:" <> discriminator), do: discriminator
  defp extract_portfolio_discriminator(_), do: nil

  defp decode_json_content(""), do: %{}

  defp decode_json_content(content) do
    case Jason.decode(content) do
      {:ok, data} -> data
      {:error, _} -> %{}
    end
  end

  defp safe_to_integer(nil), do: nil

  defp safe_to_integer(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp safe_to_integer(int) when is_integer(int), do: int
end
