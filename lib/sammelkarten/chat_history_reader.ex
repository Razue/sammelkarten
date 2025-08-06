defmodule Sammelkarten.ChatHistoryReader do
  @moduledoc """
  Module for reading and exporting Telegram chat history using the Bot API.
  
  This module provides functionality to:
  - Collect messages from Telegram chats where the bot is present
  - Store messages locally for analysis
  - Export chat history to various formats (JSON, CSV, plain text)
  - Handle pagination and batch processing
  
  Limitations:
  - Only messages sent after the bot was added to the chat are accessible
  - Bot must have appropriate permissions in the chat
  - Rate limiting applies as per Telegram Bot API limits
  """

  require Logger
  alias Sammelkarten.TelegramClient

  @doc """
  Start collecting messages from all available chats.
  This function will continuously poll for new messages and store them.
  
  Options:
  - max_messages: Maximum number of messages to collect (default: 1000)
  - poll_interval: Interval between polls in seconds (default: 5)
  - storage_path: Path to store collected messages (default: "chat_history.json")
  """
  def start_collection(opts \\ []) do
    max_messages = Keyword.get(opts, :max_messages, 1000)
    poll_interval = Keyword.get(opts, :poll_interval, 5)
    storage_path = Keyword.get(opts, :storage_path, "chat_history.json")

    Logger.info("Starting chat history collection (max: #{max_messages} messages)")
    
    {:ok, pid} = Task.start_link(fn ->
      collect_messages_loop(max_messages, poll_interval, storage_path, 0, [])
    end)

    {:ok, pid}
  end

  @doc """
  Collect messages from a specific chat.
  Returns a list of formatted messages.
  """
  def collect_chat_messages(chat_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    
    Logger.info("Collecting messages from chat #{chat_id}")
    
    case TelegramClient.get_chat_messages(chat_id, limit: limit) do
      {:ok, messages} ->
        formatted_messages = Enum.map(messages, &TelegramClient.format_message/1)
        Logger.info("Collected #{length(formatted_messages)} messages from chat #{chat_id}")
        {:ok, formatted_messages}

      {:error, error} ->
        Logger.error("Failed to collect messages from chat #{chat_id}: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Get information about all chats where the bot has received messages.
  This function analyzes stored message data to extract unique chats.
  """
  def get_active_chats(messages) when is_list(messages) do
    messages
    |> Enum.group_by(fn msg -> msg.chat_id end)
    |> Enum.map(fn {chat_id, chat_messages} ->
      first_message = List.first(chat_messages)
      %{
        chat_id: chat_id,
        chat_title: first_message.chat_title,
        chat_type: first_message.chat_type,
        message_count: length(chat_messages),
        first_message_date: first_message.date,
        last_message_date: List.last(chat_messages).date
      }
    end)
    |> Enum.sort_by(& &1.last_message_date, {:desc, DateTime})
  end

  @doc """
  Export messages to JSON format.
  """
  def export_to_json(messages, file_path \\ "chat_history.json") do
    json_data = %{
      export_date: DateTime.utc_now(),
      message_count: length(messages),
      messages: messages
    }

    case Jason.encode(json_data, pretty: true) do
      {:ok, json_string} ->
        case File.write(file_path, json_string) do
          :ok ->
            Logger.info("Exported #{length(messages)} messages to #{file_path}")
            {:ok, file_path}

          {:error, reason} ->
            Logger.error("Failed to write JSON file: #{reason}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to encode JSON: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Export messages to CSV format.
  """
  def export_to_csv(messages, file_path \\ "chat_history.csv") do
    csv_headers = [
      "message_id", "date", "chat_id", "chat_title", "chat_type",
      "from_user_id", "from_username", "from_first_name", "text", "message_type"
    ]

    csv_rows = Enum.map(messages, fn msg ->
      [
        msg.message_id,
        DateTime.to_iso8601(msg.date),
        msg.chat_id,
        msg.chat_title || "",
        msg.chat_type,
        (msg.from_user && msg.from_user.id) || "",
        (msg.from_user && msg.from_user.username) || "",
        (msg.from_user && msg.from_user.first_name) || "",
        msg.text || "",
        msg.message_type
      ]
    end)

    all_rows = [csv_headers | csv_rows]
    csv_content = Enum.map(all_rows, fn row ->
      Enum.map(row, &escape_csv_field/1) |> Enum.join(",")
    end) |> Enum.join("\n")

    case File.write(file_path, csv_content) do
      :ok ->
        Logger.info("Exported #{length(messages)} messages to #{file_path}")
        {:ok, file_path}

      {:error, reason} ->
        Logger.error("Failed to write CSV file: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Export messages to plain text format.
  """
  def export_to_text(messages, file_path \\ "chat_history.txt") do
    text_content = Enum.map(messages, fn msg ->
      user_info = if msg.from_user do
        "#{msg.from_user.first_name || "Unknown"} (@#{msg.from_user.username || "no_username"})"
      else
        "Unknown User"
      end

      date_str = DateTime.to_string(msg.date)
      chat_info = "[#{msg.chat_title || "Chat #{msg.chat_id}"}]"
      
      "#{date_str} #{chat_info} #{user_info}: #{msg.text || "[#{msg.message_type} message]"}"
    end) |> Enum.join("\n")

    header = """
    Telegram Chat History Export
    Generated: #{DateTime.utc_now() |> DateTime.to_string()}
    Total Messages: #{length(messages)}
    
    Format: [Date] [Chat] [User]: [Message]
    =====================================================
    
    """

    full_content = header <> text_content

    case File.write(file_path, full_content) do
      :ok ->
        Logger.info("Exported #{length(messages)} messages to #{file_path}")
        {:ok, file_path}

      {:error, reason} ->
        Logger.error("Failed to write text file: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Load previously saved messages from JSON file.
  """
  def load_from_json(file_path \\ "chat_history.json") do
    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content, keys: :atoms) do
          {:ok, data} ->
            messages = data.messages || []
            Logger.info("Loaded #{length(messages)} messages from #{file_path}")
            {:ok, messages}

          {:error, reason} ->
            Logger.error("Failed to decode JSON: #{reason}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to read file #{file_path}: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Filter messages by date range.
  """
  def filter_by_date_range(messages, start_date, end_date) do
    messages
    |> Enum.filter(fn msg ->
      DateTime.compare(msg.date, start_date) != :lt and
      DateTime.compare(msg.date, end_date) != :gt
    end)
  end

  @doc """
  Filter messages by chat ID.
  """
  def filter_by_chat(messages, chat_id) do
    Enum.filter(messages, fn msg -> msg.chat_id == chat_id end)
  end

  @doc """
  Search messages by text content.
  """
  def search_messages(messages, search_term) do
    search_term_lower = String.downcase(search_term)
    
    Enum.filter(messages, fn msg ->
      text = msg.text || ""
      String.contains?(String.downcase(text), search_term_lower)
    end)
  end

  # Private functions

  defp collect_messages_loop(max_messages, poll_interval, storage_path, offset, collected_messages) do
    if length(collected_messages) >= max_messages do
      Logger.info("Reached maximum message limit (#{max_messages}), stopping collection")
      export_to_json(collected_messages, storage_path)
    else
      case TelegramClient.get_updates(offset: offset, limit: 100, timeout: poll_interval) do
        {:ok, updates} ->
          new_messages = 
            updates
            |> TelegramClient.extract_messages()
            |> Enum.map(&TelegramClient.format_message/1)

          all_messages = collected_messages ++ new_messages
          new_offset = get_next_offset(updates, offset)

          if length(new_messages) > 0 do
            Logger.info("Collected #{length(new_messages)} new messages (total: #{length(all_messages)})")
          end

          :timer.sleep(poll_interval * 1000)
          collect_messages_loop(max_messages, poll_interval, storage_path, new_offset, all_messages)

        {:error, error} ->
          Logger.error("Error during message collection: #{inspect(error)}")
          :timer.sleep(poll_interval * 2 * 1000)  # Wait longer on error
          collect_messages_loop(max_messages, poll_interval, storage_path, offset, collected_messages)
      end
    end
  end

  defp get_next_offset([], current_offset), do: current_offset

  defp get_next_offset(updates, _current_offset) do
    updates
    |> Enum.map(& &1.update_id)
    |> Enum.max()
    |> Kernel.+(1)
  end

  defp escape_csv_field(field) when is_binary(field) do
    if String.contains?(field, [",", "\"", "\n", "\r"]) do
      "\"#{String.replace(field, "\"", "\"\"")}\""
    else
      field
    end
  end

  defp escape_csv_field(field), do: to_string(field)
end