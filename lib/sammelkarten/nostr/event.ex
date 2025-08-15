defmodule Sammelkarten.Nostr.Event do
  @moduledoc """
  Nostr event data structure and utilities for the Sammelkarten application.

  This module handles:
  - Event creation and validation
  - Event signing and verification
  - Custom Sammelkarten event types
  - Event serialization/deserialization
  """

  @type t :: %__MODULE__{
          id: String.t() | nil,
          pubkey: String.t(),
          created_at: integer(),
          kind: integer(),
          tags: list(list(String.t())),
          content: String.t(),
          sig: String.t() | nil
        }

  defstruct [
    :id,
    :pubkey,
    :created_at,
    :kind,
    :tags,
    :content,
    :sig
  ]

  # Custom event kinds for Sammelkarten
  @card_collection_kind 30000
  @trade_offer_kind 30001
  @trade_execution_kind 30002
  @price_alert_kind 30003
  @portfolio_snapshot_kind 30004

  # Standard Nostr kinds
  # @metadata_kind 0
  # @text_note_kind 1
  # @relay_list_kind 3

  @doc """
  Create a new unsigned event.
  """
  def new(pubkey, kind, content, tags \\ []) do
    %__MODULE__{
      pubkey: pubkey,
      created_at: DateTime.utc_now() |> DateTime.to_unix(),
      kind: kind,
      tags: tags,
      content: content
    }
  end

  @doc """
  Create a card collection event.
  """
  def card_collection(pubkey, collection_data) do
    content = Jason.encode!(collection_data)
    # NIP-33 replaceable event
    tags = [["d", "collection"]]

    new(pubkey, @card_collection_kind, content, tags)
  end

  @doc """
  Create a trade offer event.
  """
  def trade_offer(pubkey, offer_data) do
    %{
      card_id: card_id,
      # "buy" or "sell"
      offer_type: offer_type,
      price: price,
      quantity: _quantity,
      expires_at: expires_at
    } = offer_data

    content = Jason.encode!(offer_data)

    tags = [
      ["d", "trade_#{card_id}_#{System.unique_integer([:positive])}"],
      ["card", card_id],
      ["type", to_string(offer_type)],
      ["price", to_string(price)],
      ["expires", to_string(expires_at)]
    ]

    new(pubkey, @trade_offer_kind, content, tags)
  end

  @doc """
  Create a trade execution event.
  """
  def trade_execution(pubkey, execution_data) do
    %{
      trade_id: trade_id,
      buyer_pubkey: buyer_pubkey,
      seller_pubkey: seller_pubkey,
      card_id: card_id,
      price: _price,
      quantity: _quantity
    } = execution_data

    content = Jason.encode!(execution_data)

    tags = [
      ["d", "execution_#{trade_id}"],
      ["trade", trade_id],
      ["buyer", buyer_pubkey],
      ["seller", seller_pubkey],
      ["card", card_id]
    ]

    new(pubkey, @trade_execution_kind, content, tags)
  end

  @doc """
  Create a price alert event.
  """
  def price_alert(pubkey, alert_data) do
    %{
      card_id: card_id,
      # "above" or "below"
      alert_type: alert_type,
      target_price: target_price,
      active: active
    } = alert_data

    content = Jason.encode!(alert_data)

    tags = [
      ["d", "alert_#{card_id}"],
      ["card", card_id],
      ["type", to_string(alert_type)],
      ["price", to_string(target_price)],
      ["active", to_string(active)]
    ]

    new(pubkey, @price_alert_kind, content, tags)
  end

  @doc """
  Create a portfolio snapshot event.
  """
  def portfolio_snapshot(pubkey, portfolio_data) do
    content = Jason.encode!(portfolio_data)

    tags = [
      ["d", "portfolio"],
      ["total_value", to_string(portfolio_data.total_value)],
      ["card_count", to_string(length(portfolio_data.cards))]
    ]

    new(pubkey, @portfolio_snapshot_kind, content, tags)
  end

  @doc """
  Calculate the event ID (hash).
  """
  def calculate_id(event) do
    serialized = serialize_for_id(event)
    :crypto.hash(:sha256, serialized) |> Base.encode16(case: :lower)
  end

  @doc """
  Sign an event with a private key.
  """
  def sign(event, private_key) do
    event_with_id = %{event | id: calculate_id(event)}

    try do
      # Convert hex strings to binary for Curvy
      event_id_binary = Base.decode16!(event_with_id.id, case: :lower)
      private_key_binary = Base.decode16!(private_key, case: :lower)
      
      # Curvy.sign returns a binary signature, not a tuple
      signature = Curvy.sign(event_id_binary, private_key_binary)
      signature_hex = Base.encode16(signature, case: :lower)
      
      {:ok, %{event_with_id | sig: signature_hex}}
    rescue
      e ->
        {:error, "Signing failed: #{Exception.message(e)}"}
    end
  end

  @doc """
  Verify an event signature.
  """
  def verify(event) do
    require Logger

    if event.id && event.sig && event.pubkey do
      try do
        # Convert hex strings to binary
        event_id_binary = Base.decode16!(event.id, case: :lower)
        signature_binary = Base.decode16!(event.sig, case: :lower)
        pubkey_binary = Base.decode16!(event.pubkey, case: :lower)

        # Verify the signature using Curvy
        # Curvy.verify returns a boolean, not a tuple
        case Curvy.verify(signature_binary, event_id_binary, pubkey_binary) do
          true ->
            Logger.debug(
              "Signature verified successfully for pubkey: #{String.slice(event.pubkey, 0, 8)}..."
            )
            {:ok, true}

          false ->
            Logger.debug(
              "Signature verification failed for pubkey: #{String.slice(event.pubkey, 0, 8)}..."
            )
            {:ok, false}

          other ->
            Logger.warning(
              "Unexpected signature verification result for pubkey #{String.slice(event.pubkey, 0, 8)}: #{inspect(other)}"
            )
            {:error, :unexpected_result}
        end
      rescue
        e ->
          Logger.warning(
            "Exception during signature verification for pubkey #{String.slice(event.pubkey, 0, 8)}: #{Exception.message(e)}"
          )
          {:error, :verification_exception}
      end
    else
      {:error, :missing_fields}
    end
  end

  @doc """
  Check if an event is valid (has correct ID and signature).
  """
  def valid?(event) do
    calculated_id = calculate_id(event)

    event.id == calculated_id &&
      case verify(event) do
        {:ok, true} -> true
        _ -> false
      end
  end

  @doc """
  Parse an event from JSON or map.
  """
  def from_map(map) when is_map(map) do
    %__MODULE__{
      id: Map.get(map, "id"),
      pubkey: Map.get(map, "pubkey"),
      created_at: Map.get(map, "created_at"),
      kind: Map.get(map, "kind"),
      tags: Map.get(map, "tags", []),
      content: Map.get(map, "content", ""),
      sig: Map.get(map, "sig")
    }
  end

  @doc """
  Convert event to map for JSON serialization.
  """
  def to_map(event) do
    %{
      "id" => event.id,
      "pubkey" => event.pubkey,
      "created_at" => event.created_at,
      "kind" => event.kind,
      "tags" => event.tags,
      "content" => event.content,
      "sig" => event.sig
    }
  end

  @doc """
  Get the value of a specific tag.
  """
  def get_tag_value(event, tag_name) do
    event.tags
    |> Enum.find(fn [name | _] -> name == tag_name end)
    |> case do
      [_name, value | _] -> value
      _ -> nil
    end
  end

  @doc """
  Get all values for a specific tag.
  """
  def get_tag_values(event, tag_name) do
    event.tags
    |> Enum.filter(fn [name | _] -> name == tag_name end)
    |> Enum.map(fn [_name, value | _] -> value end)
  end

  @doc """
  Check if event matches a filter.
  """
  def matches_filter?(event, filter) do
    Enum.all?(filter, fn {key, value} ->
      case key do
        "ids" ->
          event.id in value

        "authors" ->
          event.pubkey in value

        "kinds" ->
          event.kind in value

        "since" ->
          event.created_at >= value

        "until" ->
          event.created_at <= value

        "#" <> tag_name ->
          tag_values = get_tag_values(event, tag_name)
          Enum.any?(value, fn v -> v in tag_values end)

        _ ->
          true
      end
    end)
  end

  @doc """
  Generate a random private key.
  """
  def generate_private_key do
    :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
  end

  @doc """
  Derive public key from private key.
  """
  def private_key_to_public(private_key) do
    try do
      # Convert hex to binary
      private_key_binary = Base.decode16!(private_key, case: :lower)
      
      # Create key from private key
      key = Curvy.Key.from_privkey(private_key_binary)
      
      # Get public key and convert to hex
      public_key_binary = Curvy.Key.to_pubkey(key)
      public_key_hex = Base.encode16(public_key_binary, case: :lower)
      
      {:ok, public_key_hex}
    rescue
      e ->
        {:error, "Failed to derive public key: #{Exception.message(e)}"}
    end
  end

  @doc """
  Convert public key to npub (bech32) format.
  """
  def pubkey_to_npub(pubkey) do
    case Base.decode16(pubkey, case: :lower) do
      {:ok, pubkey_bytes} ->
        npub = Bech32.encode("npub", pubkey_bytes)
        {:ok, npub}

      _ ->
        {:error, :invalid_pubkey}
    end
  end

  @doc """
  Convert npub (bech32) to hex public key.
  """
  def npub_to_pubkey(npub) do
    case Bech32.decode(npub) do
      {:ok, "npub", pubkey_bytes} ->
        {:ok, Base.encode16(pubkey_bytes, case: :lower)}

      _ ->
        {:error, :invalid_npub}
    end
  end

  # Private helper functions

  # defp normalize_pubkey(pubkey) when is_binary(pubkey) do
  #   # Nostr pubkeys are 32-byte hex strings (64 chars)
  #   # For Curvy verification, we need to ensure proper compression prefix

  #   # First, let's extract the actual pubkey
  #   actual_pubkey =
  #     case String.length(pubkey) do
  #       64 ->
  #         # Check if this 64-char pubkey starts with invalid prefix
  #         if String.starts_with?(pubkey, "01") do
  #           # This looks like a corrupted pubkey, strip first 2 chars
  #           String.slice(pubkey, 2..-1//1)
  #         else
  #           # Already correct length
  #           pubkey
  #         end

  #       66 ->
  #         # Strip 2-char prefix, take rest
  #         String.slice(pubkey, 2..-1//1)

  #       68 ->
  #         # Strip 4-char prefix, take rest
  #         String.slice(pubkey, 4..-1//1)

  #       _ ->
  #         # Invalid length, let try/rescue handle error
  #         pubkey
  #     end

  #   # Now ensure we have a valid hex string and add proper prefix
  #   cond do
  #     String.length(actual_pubkey) == 64 and String.match?(actual_pubkey, ~r/^[0-9a-fA-F]{64}$/) ->
  #       "02" <> String.downcase(actual_pubkey)

  #     String.length(actual_pubkey) == 62 and String.match?(actual_pubkey, ~r/^[0-9a-fA-F]{62}$/) ->
  #       # This is a 62-char pubkey that was stripped from a corrupted 64-char one
  #       "02" <> String.downcase(actual_pubkey)

  #     true ->
  #       # Invalid format, return original and let try/rescue handle the error
  #       pubkey
  #   end
  # end

  defp serialize_for_id(event) do
    serialized_data = [
      # reserved
      0,
      # pubkey
      event.pubkey,
      # created_at
      event.created_at,
      # kind
      event.kind,
      # tags
      event.tags,
      # content
      event.content
    ]

    Jason.encode!(serialized_data)
  end
end
