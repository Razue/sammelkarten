defmodule Sammelkarten.TelegramExample do
  @moduledoc """
  Example usage of the Telegram Chat History Reader.
  
  This module demonstrates how to use the Telegram chat history functionality
  with sample data and mock responses for testing purposes.
  """

  require Logger
  alias Sammelkarten.{ChatHistoryReader, TelegramCLI}

  @doc """
  Run a complete example workflow.
  This function demonstrates the full process of collecting and exporting chat history.
  """
  def run_example do
    IO.puts("🤖 Telegram Chat History Reader Example")
    IO.puts("======================================\n")

    # Step 1: Test authentication
    IO.puts("Step 1: Testing authentication...")
    case TelegramCLI.test_auth() do
      {:ok, _bot_info} ->
        IO.puts("✅ Bot authentication successful!\n")
        
        # Step 2: Demonstrate message collection
        demonstrate_collection()
        
      {:error, _error} ->
        IO.puts("❌ Authentication failed. Using demo mode...\n")
        
        # Use demo data instead
        demonstrate_with_demo_data()
    end
  end

  @doc """
  Create sample message data for testing without a real bot.
  """
  def create_demo_data do
    sample_messages = [
      %{
        message_id: 1,
        date: DateTime.utc_now() |> DateTime.add(-3600, :second),
        chat_id: -1001234567890,
        chat_title: "Elixir Developers",
        chat_type: "supergroup",
        from_user: %{
          id: 123456789,
          username: "alice_dev",
          first_name: "Alice",
          last_name: "Smith",
          is_bot: false
        },
        text: "Has anyone worked with GenServers for real-time data processing?",
        message_type: :text
      },
      %{
        message_id: 2,
        date: DateTime.utc_now() |> DateTime.add(-3500, :second),
        chat_id: -1001234567890,
        chat_title: "Elixir Developers",
        chat_type: "supergroup",
        from_user: %{
          id: 987654321,
          username: "bob_coder",
          first_name: "Bob",
          last_name: nil,
          is_bot: false
        },
        text: "Yes! I use them for financial data streams. Phoenix PubSub is great for broadcasting updates.",
        message_type: :text
      },
      %{
        message_id: 3,
        date: DateTime.utc_now() |> DateTime.add(-3200, :second),
        chat_id: -1001234567890,
        chat_title: "Elixir Developers",
        chat_type: "supergroup",
        from_user: %{
          id: 456789123,
          username: "charlie_phoenix",
          first_name: "Charlie",
          last_name: "Wilson",
          is_bot: false
        },
        text: "Check out the OTP design patterns book. It covers GenServer patterns extensively.",
        message_type: :text
      },
      %{
        message_id: 4,
        date: DateTime.utc_now() |> DateTime.add(-2800, :second),
        chat_id: -1001111111111,
        chat_title: "Bitcoin Discussion",
        chat_type: "group",
        from_user: %{
          id: 789123456,
          username: "btc_trader",
          first_name: "David",
          last_name: "Johnson",
          is_bot: false
        },
        text: "Bitcoin price just broke $70k! This bull run is incredible 🚀",
        message_type: :text
      },
      %{
        message_id: 5,
        date: DateTime.utc_now() |> DateTime.add(-2600, :second),
        chat_id: -1001111111111,
        chat_title: "Bitcoin Discussion",
        chat_type: "group",
        from_user: %{
          id: 321654987,
          username: "hodler_eva",
          first_name: "Eva",
          last_name: "Rodriguez",
          is_bot: false
        },
        text: "Been hodling since 2019. Finally seeing those gains! HODL strong 💎🙌",
        message_type: :text
      }
    ]

    # Save demo data to file
    {:ok, _path} = ChatHistoryReader.export_to_json(sample_messages, "demo_chat_history.json")
    
    IO.puts("✅ Created demo data with #{length(sample_messages)} sample messages")
    IO.puts("📁 Saved to: demo_chat_history.json\n")
    
    {:ok, sample_messages}
  end

  @doc """
  Demonstrate all export formats using demo data.
  """
  def demonstrate_exports(messages) do
    IO.puts("Step 3: Demonstrating export formats...")
    
    # Export to JSON
    case ChatHistoryReader.export_to_json(messages, "demo_export.json") do
      {:ok, json_file} ->
        IO.puts("✅ JSON export: #{json_file}")
      {:error, error} ->
        IO.puts("❌ JSON export failed: #{inspect(error)}")
    end

    # Export to CSV
    case ChatHistoryReader.export_to_csv(messages, "demo_export.csv") do
      {:ok, csv_file} ->
        IO.puts("✅ CSV export: #{csv_file}")
      {:error, error} ->
        IO.puts("❌ CSV export failed: #{inspect(error)}")
    end

    # Export to text
    case ChatHistoryReader.export_to_text(messages, "demo_export.txt") do
      {:ok, text_file} ->
        IO.puts("✅ Text export: #{text_file}")
      {:error, error} ->
        IO.puts("❌ Text export failed: #{inspect(error)}")
    end

    IO.puts("")
  end

  @doc """
  Demonstrate chat analysis features.
  """
  def demonstrate_analysis(messages) do
    IO.puts("Step 4: Analyzing chat activity...")
    
    # Get active chats
    chats = ChatHistoryReader.get_active_chats(messages)
    
    IO.puts("📊 Found #{length(chats)} active chats:")
    Enum.each(chats, fn chat ->
      IO.puts("  • #{chat.chat_title} (#{chat.message_count} messages)")
    end)

    # Search messages
    IO.puts("\n🔍 Searching for 'Bitcoin'...")
    bitcoin_messages = ChatHistoryReader.search_messages(messages, "Bitcoin")
    IO.puts("Found #{length(bitcoin_messages)} messages mentioning Bitcoin")

    # Filter by date
    one_hour_ago = DateTime.utc_now() |> DateTime.add(-3600, :second)
    now = DateTime.utc_now()
    recent_messages = ChatHistoryReader.filter_by_date_range(messages, one_hour_ago, now)
    IO.puts("📅 Found #{length(recent_messages)} messages in the last hour")

    IO.puts("")
  end

  @doc """
  Show CLI usage examples.
  """
  def demonstrate_cli_usage do
    IO.puts("Step 5: CLI Usage Examples")
    IO.puts("==========================")
    IO.puts("The following commands can be used in iex:")
    IO.puts("")
    IO.puts("# Test authentication")
    IO.puts("Sammelkarten.TelegramCLI.test_auth()")
    IO.puts("")
    IO.puts("# Analyze demo data")
    IO.puts("Sammelkarten.TelegramCLI.analyze_chats(\"demo_chat_history.json\")")
    IO.puts("")
    IO.puts("# Search demo data")
    IO.puts("Sammelkarten.TelegramCLI.search_messages(\"demo_chat_history.json\", \"Bitcoin\")")
    IO.puts("")
    IO.puts("# Export demo data")
    IO.puts("Sammelkarten.TelegramCLI.export_history(\"demo_chat_history.json\", :csv)")
    IO.puts("")
    IO.puts("# Show help")
    IO.puts("Sammelkarten.TelegramCLI.help()")
    IO.puts("")
  end

  # Private functions

  defp demonstrate_collection do
    IO.puts("Step 2: For real message collection, you would run:")
    IO.puts("Sammelkarten.TelegramCLI.start_collection(max_messages: 100)")
    IO.puts("(This requires the bot to be in active groups)\n")
    
    # Since we can't collect real messages without setup, use demo data
    demonstrate_with_demo_data()
  end

  defp demonstrate_with_demo_data do
    IO.puts("Step 2: Creating demo data for testing...")
    
    case create_demo_data() do
      {:ok, messages} ->
        demonstrate_exports(messages)
        demonstrate_analysis(messages)
        demonstrate_cli_usage()
        
        IO.puts("🎉 Example completed successfully!")
        IO.puts("Check the generated files: demo_chat_history.json, demo_export.*")
        
      {:error, error} ->
        IO.puts("❌ Failed to create demo data: #{inspect(error)}")
    end
  end
end