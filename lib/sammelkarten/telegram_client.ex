defmodule Sammelkarten.TelegramClient do
  @moduledoc """
  Telegram Bot API client for interacting with Telegram chats and retrieving messages.
  
  This module provides functionality to:
  - Authenticate with Telegram Bot API using bot token
  - Retrieve chat information and messages
  - Handle rate limiting and errors
  
  Note: Bot API has limitations compared to user clients:
  - Can only access messages after the bot was added to the group
  - Cannot access historical messages from before bot joined
  - Requires bot to be admin for some operations
  """

  require Logger

  @doc """
  Test the bot token authentication by calling getMe API.
  Returns bot information if successful.
  """
  def authenticate do
    case Telegex.get_me() do
      {:ok, bot_info} ->
        Logger.info("Telegram bot authenticated successfully: #{bot_info.username}")
        {:ok, bot_info}

      {:error, error} ->
        Logger.error("Failed to authenticate Telegram bot: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Get information about a specific chat by chat ID.
  """
  def get_chat(chat_id) do
    case Telegex.get_chat(chat_id) do
      {:ok, chat} ->
        Logger.info("Retrieved chat info for: #{chat.title || chat.username || chat_id}")
        {:ok, chat}

      {:error, error} ->
        Logger.error("Failed to get chat #{chat_id}: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Get chat administrators for a group chat.
  """
  def get_chat_administrators(chat_id) do
    case Telegex.get_chat_administrators(chat_id) do
      {:ok, administrators} ->
        Logger.info("Retrieved #{length(administrators)} administrators for chat #{chat_id}")
        {:ok, administrators}

      {:error, error} ->
        Logger.error("Failed to get administrators for chat #{chat_id}: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Get the member count of a chat.
  """
  def get_chat_member_count(chat_id) do
    case Telegex.get_chat_member_count(chat_id) do
      {:ok, count} ->
        Logger.info("Chat #{chat_id} has #{count} members")
        {:ok, count}

      {:error, error} ->
        Logger.error("Failed to get member count for chat #{chat_id}: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Retrieve updates (including messages) using long polling.
  This can be used to get recent messages from chats where the bot is present.
  
  Options:
  - offset: Identifier of the first update to be returned
  - limit: Limits the number of updates to be retrieved (1-100, default 100)
  - timeout: Timeout in seconds for long polling (0-50, default 0)
  """
  def get_updates(opts \\ []) do
    offset = Keyword.get(opts, :offset, 0)
    limit = Keyword.get(opts, :limit, 100)
    timeout = Keyword.get(opts, :timeout, 10)

    case Telegex.get_updates(offset: offset, limit: limit, timeout: timeout) do
      {:ok, updates} ->
        Logger.info("Retrieved #{length(updates)} updates")
        {:ok, updates}

      {:error, error} ->
        Logger.error("Failed to get updates: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Extract messages from updates.
  Filters updates to only return message updates.
  """
  def extract_messages(updates) when is_list(updates) do
    updates
    |> Enum.filter(fn update -> update.message != nil end)
    |> Enum.map(fn update -> update.message end)
  end

  @doc """
  Get messages from a specific chat from recent updates.
  This is a convenience function that combines get_updates and message filtering.
  """
  def get_chat_messages(chat_id, opts \\ []) do
    with {:ok, updates} <- get_updates(opts) do
      messages = 
        updates
        |> extract_messages()
        |> Enum.filter(fn message -> message.chat.id == chat_id end)

      Logger.info("Found #{length(messages)} messages for chat #{chat_id}")
      {:ok, messages}
    end
  end

  @doc """
  Format a message for display or export.
  Returns a map with formatted message data.
  """
  def format_message(message) do
    %{
      message_id: message.message_id,
      date: DateTime.from_unix!(message.date),
      chat_id: message.chat.id,
      chat_title: message.chat.title,
      chat_type: message.chat.type,
      from_user: format_user(message.from),
      text: message.text || "[non-text message]",
      message_type: determine_message_type(message)
    }
  end

  @doc """
  Get the bot's information including username and ID.
  """
  def get_bot_info do
    with {:ok, bot_info} <- Telegex.get_me() do
      {:ok, %{
        id: bot_info.id,
        username: bot_info.username,
        first_name: bot_info.first_name,
        is_bot: bot_info.is_bot
      }}
    end
  end

  # Private helper functions

  defp format_user(nil), do: nil

  defp format_user(user) do
    %{
      id: user.id,
      username: user.username,
      first_name: user.first_name,
      last_name: user.last_name,
      is_bot: user.is_bot || false
    }
  end

  defp determine_message_type(message) do
    cond do
      message.text -> :text
      message.photo -> :photo
      message.video -> :video
      message.document -> :document
      message.audio -> :audio
      message.voice -> :voice
      message.sticker -> :sticker
      message.location -> :location
      message.contact -> :contact
      true -> :other
    end
  end
end