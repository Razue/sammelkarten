defmodule Sammelkarten.Lightning do
  @moduledoc """
  Lightning Network integration for secure escrow trading.
  
  This module provides functionality for:
  - Creating Lightning Network payment channels for escrow
  - Managing escrow-secured trades
  - Handling atomic swaps for card trading
  - Integration with popular Lightning wallets
  """
  
  require Logger
  
  # Lightning Network integration types
  @type payment_hash :: binary()
  @type payment_request :: String.t() 
  @type preimage :: binary()
  @type escrow_id :: String.t()
  
  defstruct [
    :escrow_id,
    :amount_sats,
    :buyer_pubkey,
    :seller_pubkey,
    :card_id,
    :quantity,
    :payment_hash,
    :payment_request,
    :status,
    :created_at,
    :expires_at
  ]
  
  # Escrow statuses
  @escrow_pending "pending"
  @escrow_funded "funded"
  @escrow_completed "completed"
  @escrow_expired "expired"
  @escrow_cancelled "cancelled"
  
  @doc """
  Create a new Lightning escrow for a card trade.
  
  The escrow will hold the payment until the trade is completed.
  Both parties must sign completion before funds are released.
  """
  def create_escrow(buyer_pubkey, seller_pubkey, card_id, quantity, amount_sats) do
    escrow_id = generate_escrow_id()
    expires_at = DateTime.add(DateTime.utc_now(), 24 * 60 * 60, :second) # 24 hours
    
    escrow = %__MODULE__{
      escrow_id: escrow_id,
      amount_sats: amount_sats,
      buyer_pubkey: buyer_pubkey,
      seller_pubkey: seller_pubkey,
      card_id: card_id,
      quantity: quantity,
      status: @escrow_pending,
      created_at: DateTime.utc_now(),
      expires_at: expires_at
    }
    
    # For now, simulate Lightning payment request generation
    # In a real implementation, this would integrate with LND, CLN, or similar
    case generate_payment_request(amount_sats, escrow_id) do
      {:ok, payment_request, payment_hash} ->
        escrow = %{escrow | 
          payment_request: payment_request,
          payment_hash: payment_hash
        }
        
        # Store escrow in database
        case store_escrow(escrow) do
          :ok ->
            Logger.info("Created Lightning escrow #{escrow_id} for #{amount_sats} sats")
            {:ok, escrow}
          {:error, reason} ->
            {:error, reason}
        end
        
      {:error, reason} ->
        {:error, {:payment_generation_failed, reason}}
    end
  end
  
  @doc """
  Check the status of a Lightning escrow.
  """
  def get_escrow(escrow_id) do
    # In a real implementation, this would query the database
    # For now, return a simulated response
    case :mnesia.dirty_read(:lightning_escrows, escrow_id) do
      [escrow] -> {:ok, escrow}
      [] -> {:error, :not_found}
    end
  end
  
  @doc """
  Fund an escrow by paying the Lightning invoice.
  
  This would typically be called after the buyer pays the generated invoice.
  """
  def fund_escrow(escrow_id, payment_preimage) do
    case get_escrow(escrow_id) do
      {:ok, escrow} when escrow.status == @escrow_pending ->
        # Verify payment preimage matches payment hash
        if verify_preimage(payment_preimage, escrow.payment_hash) do
          updated_escrow = %{escrow | status: @escrow_funded}
          
          case update_escrow(updated_escrow) do
            :ok ->
              Logger.info("Funded Lightning escrow #{escrow_id}")
              
              # Publish Nostr event about funded escrow
              publish_escrow_event(updated_escrow, :funded)
              
              {:ok, updated_escrow}
            {:error, reason} ->
              {:error, reason}
          end
        else
          {:error, :invalid_preimage}
        end
        
      {:ok, escrow} ->
        {:error, {:invalid_status, escrow.status}}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Complete an escrow trade after both parties confirm.
  
  This releases the escrowed funds to the seller and transfers card ownership.
  """
  def complete_escrow(escrow_id, buyer_signature, seller_signature) do
    case get_escrow(escrow_id) do
      {:ok, escrow} when escrow.status == @escrow_funded ->
        # Verify both parties have signed the completion
        if verify_signatures(escrow, buyer_signature, seller_signature) do
          # Transfer card ownership
          case transfer_card_ownership(escrow) do
            :ok ->
              # Release escrowed funds to seller
              case release_funds(escrow) do
                :ok ->
                  updated_escrow = %{escrow | status: @escrow_completed}
                  update_escrow(updated_escrow)
                  
                  Logger.info("Completed Lightning escrow #{escrow_id}")
                  
                  # Publish Nostr event about completed trade
                  publish_escrow_event(updated_escrow, :completed)
                  
                  {:ok, updated_escrow}
                  
                {:error, reason} ->
                  {:error, {:fund_release_failed, reason}}
              end
              
            {:error, reason} ->
              {:error, {:card_transfer_failed, reason}}
          end
        else
          {:error, :invalid_signatures}
        end
        
      {:ok, escrow} ->
        {:error, {:invalid_status, escrow.status}}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Cancel an unfunded escrow.
  """
  def cancel_escrow(escrow_id, canceller_pubkey) do
    case get_escrow(escrow_id) do
      {:ok, escrow} when escrow.status == @escrow_pending ->
        # Only buyer or seller can cancel
        if canceller_pubkey in [escrow.buyer_pubkey, escrow.seller_pubkey] do
          updated_escrow = %{escrow | status: @escrow_cancelled}
          
          case update_escrow(updated_escrow) do
            :ok ->
              Logger.info("Cancelled Lightning escrow #{escrow_id}")
              publish_escrow_event(updated_escrow, :cancelled)
              {:ok, updated_escrow}
            {:error, reason} ->
              {:error, reason}
          end
        else
          {:error, :unauthorized}
        end
        
      {:ok, escrow} ->
        {:error, {:cannot_cancel_status, escrow.status}}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Clean up expired escrows.
  
  This should be called periodically to handle escrows that have expired.
  """
  def cleanup_expired_escrows do
    now = DateTime.utc_now()
    
    # Find all expired pending escrows
    expired_escrows = 
      :mnesia.dirty_select(:lightning_escrows, [
        {{:lightning_escrows, :"$1", :"$2", :"$3", :"$4", :"$5", :"$6", :"$7", 
          :"$8", @escrow_pending, :"$10", :"$11"},
         [{:<, :"$11", now}],
         [:"$_"]}
      ])
    
    Enum.each(expired_escrows, fn escrow ->
      updated_escrow = %{escrow | status: @escrow_expired}
      update_escrow(updated_escrow)
      Logger.info("Expired Lightning escrow #{escrow.escrow_id}")
    end)
    
    length(expired_escrows)
  end
  
  # Private helper functions
  
  defp generate_escrow_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
  
  defp generate_payment_request(amount_sats, escrow_id) do
    # In a real implementation, this would call into LND/CLN APIs
    # For simulation, we generate mock payment request and hash
    payment_hash = :crypto.hash(:sha256, escrow_id <> Integer.to_string(amount_sats))
    
    # Mock Lightning payment request (BOLT11 format simulation)
    payment_request = "lnbc#{amount_sats}u1p#{Base.encode16(payment_hash, case: :lower)}"
    
    {:ok, payment_request, payment_hash}
  end
  
  defp verify_preimage(preimage, payment_hash) do
    # In a real implementation, verify that SHA256(preimage) == payment_hash
    # For simulation, we'll accept any preimage
    computed_hash = :crypto.hash(:sha256, preimage)
    computed_hash == payment_hash
  end
  
  defp verify_signatures(_escrow, buyer_signature, seller_signature) do
    # In a real implementation, verify Nostr signatures from both parties
    # For simulation, we'll accept any signatures
    is_binary(buyer_signature) and is_binary(seller_signature) and
    byte_size(buyer_signature) > 0 and byte_size(seller_signature) > 0
  end
  
  defp transfer_card_ownership(escrow) do
    # Transfer card from seller to buyer in user collections
    case Sammelkarten.Cards.transfer_card(
      escrow.seller_pubkey, 
      escrow.buyer_pubkey, 
      escrow.card_id, 
      escrow.quantity
    ) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp release_funds(escrow) do
    # In a real implementation, this would release Lightning funds to seller
    # For simulation, we'll always succeed
    Logger.info("Releasing #{escrow.amount_sats} sats to #{escrow.seller_pubkey}")
    :ok
  end
  
  defp store_escrow(escrow) do
    transaction = fn ->
      :mnesia.write({:lightning_escrows, 
        escrow.escrow_id,
        escrow.amount_sats,
        escrow.buyer_pubkey,
        escrow.seller_pubkey,
        escrow.card_id,
        escrow.quantity,
        escrow.payment_hash,
        escrow.payment_request,
        escrow.status,
        escrow.created_at,
        escrow.expires_at
      })
    end
    
    case :mnesia.transaction(transaction) do
      {:atomic, :ok} -> :ok
      {:aborted, reason} -> {:error, reason}
    end
  end
  
  defp update_escrow(escrow) do
    store_escrow(escrow)
  end
  
  defp publish_escrow_event(escrow, event_type) do
    # Publish Nostr event about escrow status change
    event_content = %{
      escrow_id: escrow.escrow_id,
      event_type: event_type,
      amount_sats: escrow.amount_sats,
      card_id: escrow.card_id,
      quantity: escrow.quantity,
      status: escrow.status
    }
    
    # This would use the Nostr client to publish the event
    # For now, we'll just log it
    Logger.info("Escrow event: #{inspect(event_content)}")
  end
end