defmodule Sammelkarten.Nostr.Publisher do
  @moduledoc """
  Publishes card definitions and other events to Nostr relays.
  Handles admin key management and event publishing workflow.
  """

  alias Sammelkarten.Nostr.{Event, Signer, Schema}
  alias Sammelkarten.{Cards, Card, UserCollection}

  require Logger

  @doc """
  Publish a card definition event (32121) to relays.
  Takes a card struct and publishes as parameterized replaceable event.
  """
  @spec publish_card_definition(map()) :: {:ok, Event.t()} | {:error, term}
  def publish_card_definition(card_map) when is_map(card_map) do
    with {:ok, admin_keys} <- get_admin_keys(),
         event <- Event.card_definition(admin_keys.pub, card_map),
         {:ok, validated_event} <- Schema.validate(event),
         {:ok, signed_event} <- Signer.sign(validated_event, admin_keys.priv),
         {:ok, _result} <- publish_to_relays(signed_event) do
      Logger.info("Published card definition for #{card_map.card_id}")
      {:ok, signed_event}
    else
      {:error, reason} = error ->
        Logger.error("Failed to publish card definition for #{card_map.card_id}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Publish multiple card definitions in batch.
  """
  @spec publish_card_definitions([map()]) :: {:ok, [Event.t()]} | {:error, term}
  def publish_card_definitions(card_maps) when is_list(card_maps) do
    results = 
      Enum.map(card_maps, fn card_map ->
        case publish_card_definition(card_map) do
          {:ok, event} -> event
          {:error, reason} ->
            Logger.warning("Skipping card #{card_map.card_id}: #{inspect(reason)}")
            nil
        end
      end)

    published_events = Enum.reject(results, &is_nil/1)
    
    if length(published_events) > 0 do
      {:ok, published_events}
    else
      {:error, :no_events_published}
    end
  end

  @doc """
  Publish user collection snapshot event (32122).
  """
  @spec publish_user_collection(String.t(), map(), String.t()) :: {:ok, Event.t()} | {:error, term}
  def publish_user_collection(user_pubkey, collection_map, user_privkey) do
    with event <- Event.user_collection(user_pubkey, collection_map),
         {:ok, validated_event} <- Schema.validate(event),
         {:ok, signed_event} <- Signer.sign(validated_event, user_privkey),
         {:ok, _result} <- publish_to_relays(signed_event) do
      Logger.info("Published user collection for #{String.slice(user_pubkey, 0, 8)}...")
      {:ok, signed_event}
    else
      {:error, reason} = error ->
        Logger.error("Failed to publish user collection: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Publish user collection snapshot from current local state.
  This is a convenience function that aggregates the collection and publishes it.
  """
  @spec publish_user_collection_snapshot(String.t(), String.t()) :: {:ok, Event.t()} | {:error, term}
  def publish_user_collection_snapshot(user_pubkey, user_privkey) do
    with {:ok, snapshot} <- UserCollection.create_collection_snapshot(user_pubkey),
         {:ok, collection_data} <- UserCollection.decode_collection_json(snapshot.json_content),
         event <- Event.user_collection(user_pubkey, collection_data.cards),
         {:ok, validated_event} <- Schema.validate(event),
         {:ok, signed_event} <- Signer.sign(validated_event, user_privkey),
         {:ok, _result} <- publish_to_relays(signed_event) do
      Logger.info("Published collection snapshot for #{String.slice(user_pubkey, 0, 8)}... (#{collection_data.total_cards} cards)")
      {:ok, signed_event}
    else
      {:error, reason} = error ->
        Logger.error("Failed to publish collection snapshot: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Publish portfolio snapshot event (32126).
  """
  @spec publish_portfolio_snapshot(String.t(), map(), String.t()) :: {:ok, Event.t()} | {:error, term}
  def publish_portfolio_snapshot(user_pubkey, portfolio_data, user_privkey) do
    with event <- Event.portfolio_snapshot(user_pubkey, portfolio_data),
         {:ok, validated_event} <- Schema.validate(event),
         {:ok, signed_event} <- Signer.sign(validated_event, user_privkey),
         {:ok, _result} <- publish_to_relays(signed_event) do
      Logger.info("Published portfolio snapshot for #{String.slice(user_pubkey, 0, 8)}...")
      {:ok, signed_event}
    else
      {:error, reason} = error ->
        Logger.error("Failed to publish portfolio snapshot: #{inspect(reason)}")
        error
    end
  end

  # Private functions

  defp get_admin_keys do
    case System.get_env("NOSTR_ADMIN_PRIVKEY") do
      nil ->
        {:error, :no_admin_key}
      
      privkey when is_binary(privkey) ->
        case Event.private_key_to_public(privkey) do
          {:ok, pubkey} -> {:ok, %{priv: privkey, pub: pubkey}}
          error -> error
        end
    end
  end

  defp publish_to_relays(event) do
    # For now, just return success. In Phase 10, this will implement actual relay publishing
    # TODO: Implement actual relay client publishing
    Logger.debug("Would publish event #{event.id} to relays")
    {:ok, :published}
  end
end