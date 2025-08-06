defmodule Sammelkarten.TelegramCLI do
  @moduledoc """
  Command-line interface for Telegram chat history operations.
  
  This module provides a simple interface for common operations:
  - Testing bot authentication
  - Collecting messages from chats
  - Exporting chat history to various formats
  - Analyzing chat activity
  """

  require Logger
  alias Sammelkarten.{TelegramClient, ChatHistoryReader}

  @doc """
  Test if the Telegram bot is properly configured and authenticated.
  
  Usage:
    iex> Sammelkarten.TelegramCLI.test_auth()
  """
  def test_auth do
    IO.puts("Testing Telegram bot authentication...")
    
    case TelegramClient.authenticate() do
      {:ok, bot_info} ->
        IO.puts("✅ Authentication successful!")
        IO.puts("Bot name: #{bot_info.first_name}")
        IO.puts("Bot username: @#{bot_info.username}")
        IO.puts("Bot ID: #{bot_info.id}")
        {:ok, bot_info}

      {:error, error} ->
        IO.puts("❌ Authentication failed!")
        IO.puts("Error: #{inspect(error)}")
        IO.puts("\nPlease check:")
        IO.puts("1. TELEGRAM_BOT_TOKEN environment variable is set")
        IO.puts("2. Token is valid and bot is active")
        IO.puts("3. Network connectivity")
        {:error, error}
    end
  end

  @doc """
  Start collecting messages from all available chats.
  
  Options:
  - max_messages: Maximum number of messages to collect (default: 1000)
  - poll_interval: Seconds between polls (default: 5)  
  - output_file: File to save messages (default: "chat_history.json")
  
  Usage:
    iex> Sammelkarten.TelegramCLI.start_collection(max_messages: 500)
  """
  def start_collection(opts \\ []) do
    max_messages = Keyword.get(opts, :max_messages, 1000)
    poll_interval = Keyword.get(opts, :poll_interval, 5)
    output_file = Keyword.get(opts, :output_file, "chat_history.json")

    IO.puts("🚀 Starting message collection...")
    IO.puts("Max messages: #{max_messages}")
    IO.puts("Poll interval: #{poll_interval} seconds")
    IO.puts("Output file: #{output_file}")
    IO.puts("Press Ctrl+C to stop\n")

    case ChatHistoryReader.start_collection(
      max_messages: max_messages,
      poll_interval: poll_interval,
      storage_path: output_file
    ) do
      {:ok, pid} ->
        IO.puts("✅ Collection started successfully (PID: #{inspect(pid)})")
        {:ok, pid}

      {:error, error} ->
        IO.puts("❌ Failed to start collection: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Get recent messages from a specific chat.
  
  Usage:
    iex> Sammelkarten.TelegramCLI.get_chat_messages(-1234567890, limit: 50)
  """
  def get_chat_messages(chat_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    IO.puts("📥 Collecting messages from chat #{chat_id}...")
    
    case ChatHistoryReader.collect_chat_messages(chat_id, limit: limit) do
      {:ok, messages} ->
        IO.puts("✅ Collected #{length(messages)} messages")
        
        if length(messages) > 0 do
          IO.puts("\nSample messages:")
          messages
          |> Enum.take(3)
          |> Enum.each(fn msg ->
            user = if msg.from_user, do: msg.from_user.first_name || "Unknown", else: "Unknown"
            IO.puts("  #{DateTime.to_string(msg.date)} - #{user}: #{String.slice(msg.text || "[non-text]", 0, 50)}...")
          end)
        end

        {:ok, messages}

      {:error, error} ->
        IO.puts("❌ Failed to collect messages: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Export chat history to different formats.
  
  Usage:
    iex> Sammelkarten.TelegramCLI.export_history("chat_history.json", :csv, "exported_chat.csv")
  """
  def export_history(input_file \\ "chat_history.json", format \\ :json, output_file \\ nil) do
    IO.puts("📤 Exporting chat history...")
    IO.puts("Input: #{input_file}")
    IO.puts("Format: #{format}")

    case ChatHistoryReader.load_from_json(input_file) do
      {:ok, messages} ->
        IO.puts("✅ Loaded #{length(messages)} messages")

        result = case format do
          :json ->
            output = output_file || "exported_chat.json"
            ChatHistoryReader.export_to_json(messages, output)

          :csv ->
            output = output_file || "exported_chat.csv"
            ChatHistoryReader.export_to_csv(messages, output)

          :text ->
            output = output_file || "exported_chat.txt"
            ChatHistoryReader.export_to_text(messages, output)

          _ ->
            IO.puts("❌ Unsupported format: #{format}")
            IO.puts("Supported formats: :json, :csv, :text")
            {:error, :unsupported_format}
        end

        case result do
          {:ok, file_path} ->
            IO.puts("✅ Exported to: #{file_path}")
            {:ok, file_path}

          {:error, error} ->
            IO.puts("❌ Export failed: #{inspect(error)}")
            {:error, error}
        end

      {:error, error} ->
        IO.puts("❌ Failed to load input file: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Analyze chat activity from collected messages.
  
  Usage:
    iex> Sammelkarten.TelegramCLI.analyze_chats("chat_history.json")
  """
  def analyze_chats(input_file \\ "chat_history.json") do
    IO.puts("📊 Analyzing chat activity...")

    case ChatHistoryReader.load_from_json(input_file) do
      {:ok, messages} ->
        IO.puts("✅ Loaded #{length(messages)} messages")
        
        chats = ChatHistoryReader.get_active_chats(messages)
        
        IO.puts("\n📋 Active Chats Summary:")
        IO.puts("Total chats: #{length(chats)}")
        
        chats
        |> Enum.with_index(1)
        |> Enum.each(fn {chat, index} ->
          IO.puts("\n#{index}. #{chat.chat_title || "Chat #{chat.chat_id}"}")
          IO.puts("   Type: #{chat.chat_type}")
          IO.puts("   Messages: #{chat.message_count}")
          IO.puts("   First message: #{DateTime.to_string(chat.first_message_date)}")
          IO.puts("   Last message: #{DateTime.to_string(chat.last_message_date)}")
          IO.puts("   Chat ID: #{chat.chat_id}")
        end)

        {:ok, chats}

      {:error, error} ->
        IO.puts("❌ Failed to load input file: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Search for messages containing specific text.
  
  Usage:
    iex> Sammelkarten.TelegramCLI.search_messages("chat_history.json", "bitcoin")
  """
  def search_messages(input_file \\ "chat_history.json", search_term) do
    IO.puts("🔍 Searching for: '#{search_term}'")

    case ChatHistoryReader.load_from_json(input_file) do
      {:ok, messages} ->
        results = ChatHistoryReader.search_messages(messages, search_term)
        
        IO.puts("✅ Found #{length(results)} matching messages")
        
        if length(results) > 0 do
          IO.puts("\nTop 5 results:")
          results
          |> Enum.take(5)
          |> Enum.with_index(1)
          |> Enum.each(fn {msg, index} ->
            user = if msg.from_user, do: msg.from_user.first_name || "Unknown", else: "Unknown"
            chat = msg.chat_title || "Chat #{msg.chat_id}"
            IO.puts("\n#{index}. [#{chat}] #{user} - #{DateTime.to_string(msg.date)}")
            IO.puts("   #{msg.text}")
          end)
        end

        {:ok, results}

      {:error, error} ->
        IO.puts("❌ Failed to load input file: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Show usage examples and help information.
  """
  def help do
    IO.puts("""
    🤖 Telegram Chat History Reader - Usage Examples

    1. Test bot authentication:
       iex> Sammelkarten.TelegramCLI.test_auth()

    2. Start collecting messages (runs continuously):
       iex> Sammelkarten.TelegramCLI.start_collection(max_messages: 500)

    3. Get messages from a specific chat:
       iex> Sammelkarten.TelegramCLI.get_chat_messages(-1234567890, limit: 50)

    4. Export collected messages:
       iex> Sammelkarten.TelegramCLI.export_history("chat_history.json", :csv)
       iex> Sammelkarten.TelegramCLI.export_history("chat_history.json", :text)

    5. Analyze chat activity:
       iex> Sammelkarten.TelegramCLI.analyze_chats()

    6. Search messages:
       iex> Sammelkarten.TelegramCLI.search_messages("chat_history.json", "bitcoin")

    📝 Setup Requirements:
    1. Create a Telegram bot via @BotFather
    2. Set TELEGRAM_BOT_TOKEN environment variable
    3. Add bot to desired groups/chats
    4. Run test_auth() to verify setup

    ⚠️  Limitations:
    - Only messages sent after bot was added are accessible
    - Bot needs appropriate permissions in group chats
    - Rate limiting applies (typically 30 requests/second)
    """)
  end
end