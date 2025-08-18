defmodule Sammelkarten.Nostr.NIP05 do
  @moduledoc """
  NIP-05 DNS-based internet identifier mapping implementation.
  
  Provides functions to:
  - Resolve NIP-05 identifiers to public keys
  - Verify public keys against NIP-05 identifiers 
  - Cache resolution results for performance
  
  NIP-05 format: <local-part>@<domain>
  Example: ralph21@nostrnostr.com
  """

  require Logger

  @type nip05_identifier :: String.t()
  @type pubkey :: String.t() 
  @type domain :: String.t()
  @type local_part :: String.t()

  # Cache timeout: 15 minutes
  @cache_timeout_ms 15 * 60 * 1000

  @doc """
  Resolve a NIP-05 identifier to a public key.
  
  Returns {:ok, pubkey} if successful, {:error, reason} otherwise.
  
  ## Examples
  
      iex> resolve("ralph21@nostrnostr.com")
      {:ok, "b0635d6a9851d3aed0cd6c495b282167acf761729078d975fc341b22650b07b9"}
      
      iex> resolve("invalid@domain.com")
      {:error, :not_found}
  """
  @spec resolve(nip05_identifier()) :: {:ok, pubkey()} | {:error, atom()}
  def resolve(identifier) when is_binary(identifier) do
    case parse_identifier(identifier) do
      {:ok, local_part, domain} ->
        # Check cache first
        cache_key = "nip05:#{identifier}"
        
        case get_cache(cache_key) do
          {:ok, pubkey} -> 
            {:ok, pubkey}
          :miss ->
            # Fetch from network
            case fetch_nostr_json(domain, local_part) do
              {:ok, pubkey} ->
                # Cache the result
                set_cache(cache_key, pubkey)
                {:ok, pubkey}
              error ->
                error
            end
        end
        
      error ->
        error
    end
  end

  @doc """
  Verify that a public key matches a NIP-05 identifier.
  
  Returns {:ok, true} if the verification succeeds, {:error, reason} otherwise.
  
  ## Examples
  
      iex> verify("ralph21@nostrnostr.com", "b0635d6a...")
      {:ok, true}
      
      iex> verify("ralph21@nostrnostr.com", "invalid_key")
      {:error, :verification_failed}
  """
  @spec verify(nip05_identifier(), pubkey()) :: {:ok, true} | {:error, atom()}
  def verify(identifier, pubkey) when is_binary(identifier) and is_binary(pubkey) do
    case resolve(identifier) do
      {:ok, resolved_pubkey} ->
        if String.downcase(resolved_pubkey) == String.downcase(pubkey) do
          {:ok, true}
        else
          {:error, :verification_failed}
        end
      error ->
        error
    end
  end

  @doc """
  Check if a string is a valid NIP-05 identifier format.
  
  ## Examples
  
      iex> valid_identifier?("ralph21@nostrnostr.com")
      true
      
      iex> valid_identifier?("invalid")
      false
  """
  @spec valid_identifier?(String.t()) :: boolean()
  def valid_identifier?(identifier) when is_binary(identifier) do
    case parse_identifier(identifier) do
      {:ok, _local_part, _domain} -> true
      _ -> false
    end
  end

  def valid_identifier?(_), do: false

  @doc """
  Parse a NIP-05 identifier into local part and domain.
  
  ## Examples
  
      iex> parse_identifier("ralph21@nostrnostr.com")
      {:ok, "ralph21", "nostrnostr.com"}
      
      iex> parse_identifier("_@example.com")
      {:ok, "_", "example.com"}
  """
  @spec parse_identifier(nip05_identifier()) :: {:ok, local_part(), domain()} | {:error, atom()}
  def parse_identifier(identifier) when is_binary(identifier) do
    case String.split(identifier, "@") do
      [local_part, domain] when local_part != "" and domain != "" ->
        if valid_local_part?(local_part) and valid_domain?(domain) do
          {:ok, local_part, domain}
        else
          {:error, :invalid_format}
        end
      _ ->
        {:error, :invalid_format}
    end
  end

  # Private Functions

  # Fetch nostr.json from domain
  defp fetch_nostr_json(domain, local_part) do
    url = "https://#{domain}/.well-known/nostr.json?name=#{local_part}"
    
    request = Finch.build(:get, url, [
      {"accept", "application/json"},
      {"user-agent", "Sammelkarten/1.0"}
    ])
    
    case Finch.request(request, Sammelkarten.Finch, receive_timeout: 10_000) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        parse_nostr_json(body, local_part)
        
      {:ok, %Finch.Response{status: status}} ->
        Logger.warning("NIP-05 fetch failed for #{url}: HTTP #{status}")
        {:error, :http_error}
        
      {:error, reason} ->
        Logger.warning("NIP-05 fetch failed for #{url}: #{inspect(reason)}")
        {:error, :network_error}
    end
  end

  # Parse the nostr.json response
  defp parse_nostr_json(body, local_part) do
    case Jason.decode(body) do
      {:ok, %{"names" => names}} when is_map(names) ->
        case Map.get(names, local_part) do
          pubkey when is_binary(pubkey) ->
            if valid_hex_pubkey?(pubkey) do
              {:ok, pubkey}
            else
              {:error, :invalid_pubkey}
            end
          _ ->
            {:error, :not_found}
        end
        
      {:ok, _} ->
        {:error, :invalid_json_format}
        
      {:error, _} ->
        {:error, :invalid_json}
    end
  end

  # Validate local part (NIP-05 spec: a-z0-9-_.)
  defp valid_local_part?(local_part) do
    Regex.match?(~r/^[a-z0-9\-_.]+$/i, local_part)
  end

  # Basic domain validation
  defp valid_domain?(domain) do
    Regex.match?(~r/^[a-z0-9.-]+\.[a-z]{2,}$/i, domain)
  end

  # Validate hex public key format (64 char hex string)
  defp valid_hex_pubkey?(pubkey) when is_binary(pubkey) do
    case String.length(pubkey) do
      64 -> 
        case Base.decode16(pubkey, case: :mixed) do
          {:ok, _} -> true
          _ -> false
        end
      _ -> 
        false
    end
  end

  # Simple in-memory cache using ETS
  defp get_cache(key) do
    case :ets.lookup(:nip05_cache, key) do
      [{^key, value, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at do
          {:ok, value}
        else
          :ets.delete(:nip05_cache, key)
          :miss
        end
      [] ->
        :miss
    end
  rescue
    ArgumentError -> 
      # Table doesn't exist, create it
      init_cache()
      :miss
  end

  defp set_cache(key, value) do
    expires_at = System.monotonic_time(:millisecond) + @cache_timeout_ms
    :ets.insert(:nip05_cache, {key, value, expires_at})
  rescue
    ArgumentError ->
      # Table doesn't exist, create it and retry
      init_cache()
      set_cache(key, value)
  end

  defp init_cache do
    :ets.new(:nip05_cache, [:set, :public, :named_table])
  rescue
    ArgumentError ->
      # Table already exists
      :ok
  end
end