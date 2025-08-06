# Telegram Chat History Reader

An Elixir implementation for reading Telegram chat group history using the Telegram Bot API.

## Overview

This implementation provides functionality to:
- Connect to Telegram using Bot API (not full MTProto client)
- Read messages from groups where the bot is present
- Export chat history to JSON, CSV, and plain text formats
- Search and analyze message data
- Handle rate limiting and error recovery

## Important Limitations

⚠️ **Bot API Limitations:**
- **No historical data**: Can only read messages sent AFTER the bot was added to the group
- **Bot permissions**: Bot needs to be added to the group and have message reading permissions
- **Rate limiting**: Telegram Bot API has rate limits (typically 30 requests/second)
- **No user client features**: Cannot access full chat history like a user client would

For full historical chat data access, you would need:
1. MTProto user client implementation (complex, deprecated Elixir libraries)
2. Telegram's TDLib (C++ library with compilation issues on some systems)
3. Manual export from Telegram Desktop application

## Setup Instructions

### 1. Create a Telegram Bot

1. Message [@BotFather](https://t.me/botfather) on Telegram
2. Create a new bot with `/newbot`
3. Get your bot token (format: `123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11`)
4. Add the bot to your target group chats

### 2. Configure Environment

Set your bot token as an environment variable:

```bash
export TELEGRAM_BOT_TOKEN="your_bot_token_here"
```

### 3. Install Dependencies

The Telegex dependency is already added to `mix.exs`. Run:

```bash
mix deps.get
mix compile
```

## Usage Examples

### Start IEx Console

```bash
iex -S mix
```

### 1. Test Authentication

```elixir
# Test if bot is properly configured
Sammelkarten.TelegramCLI.test_auth()
```

### 2. Collect Messages

```elixir
# Start continuous message collection (runs in background)
Sammelkarten.TelegramCLI.start_collection(max_messages: 2, poll_interval: 5)

# Get messages from a specific chat ID
Sammelkarten.TelegramCLI.get_chat_messages(-1234567890, limit: 100)
```

### 3. Export Data

```elixir
# Export to different formats
Sammelkarten.TelegramCLI.export_history("chat_history.json", :csv, "chat_export.csv")
Sammelkarten.TelegramCLI.export_history("chat_history.json", :text, "chat_export.txt")
```

### 4. Analyze Chats

```elixir
# Analyze collected messages
Sammelkarten.TelegramCLI.analyze_chats("chat_history.json")

# Search for specific content
Sammelkarten.TelegramCLI.search_messages("chat_history.json", "bitcoin")
```

### 5. Help

```elixir
# Show all available commands
Sammelkarten.TelegramCLI.help()
```

## Finding Chat IDs

To get chat IDs for groups:

1. Add your bot to the group
2. Start message collection
3. Send a message in the group
4. Check the collected data for the chat ID

Alternatively, you can:
- Forward a message from the group to [@userinfobot](https://t.me/userinfobot)
- Use Telegram web client developer tools
- Add the bot and check logs when it receives messages

## File Structure

The implementation consists of three main modules:

### `Sammelkarten.TelegramClient`
- Low-level Telegram Bot API wrapper
- Authentication and basic API calls
- Message formatting utilities

### `Sammelkarten.ChatHistoryReader`
- Message collection and storage
- Export functionality (JSON, CSV, text)
- Search and filtering capabilities

### `Sammelkarten.TelegramCLI`
- User-friendly command-line interface
- Common operation shortcuts
- Help and examples

## Output Formats

### JSON Format
```json
{
  "export_date": "2025-01-01T12:00:00Z",
  "message_count": 150,
  "messages": [
    {
      "message_id": 123,
      "date": "2025-01-01T10:30:00Z",
      "chat_id": -1234567890,
      "chat_title": "Example Group",
      "chat_type": "group",
      "from_user": {
        "id": 987654321,
        "username": "user123",
        "first_name": "John"
      },
      "text": "Hello, world!",
      "message_type": "text"
    }
  ]
}
```

### CSV Format
```csv
message_id,date,chat_id,chat_title,chat_type,from_user_id,from_username,from_first_name,text,message_type
123,2025-01-01T10:30:00Z,-1234567890,Example Group,group,987654321,user123,John,"Hello, world!",text
```

### Text Format
```
Telegram Chat History Export
Generated: 2025-01-01 12:00:00Z
Total Messages: 150

Format: [Date] [Chat] [User]: [Message]
=====================================================

2025-01-01 10:30:00Z [Example Group] John (@user123): Hello, world!
```

## Advanced Usage

### Direct Module Usage

```elixir
# Use modules directly for more control
alias Sammelkarten.{TelegramClient, ChatHistoryReader}

# Authenticate
{:ok, bot_info} = TelegramClient.authenticate()

# Get updates
{:ok, updates} = TelegramClient.get_updates(limit: 100)

# Extract and format messages
messages = 
  updates
  |> TelegramClient.extract_messages()
  |> Enum.map(&TelegramClient.format_message/1)

# Export to file
{:ok, _path} = ChatHistoryReader.export_to_json(messages, "my_export.json")
```

### Custom Message Processing

```elixir
# Load and process messages
{:ok, messages} = ChatHistoryReader.load_from_json("chat_history.json")

# Filter by date range
filtered = ChatHistoryReader.filter_by_date_range(
  messages, 
  ~U[2025-01-01 00:00:00Z], 
  ~U[2025-01-31 23:59:59Z]
)

# Filter by specific chat
chat_messages = ChatHistoryReader.filter_by_chat(messages, -1234567890)

# Search content
results = ChatHistoryReader.search_messages(messages, "keyword")
```

## Troubleshooting

### Common Issues

1. **"Authentication failed"**
   - Check `TELEGRAM_BOT_TOKEN` environment variable
   - Verify token is correct and bot is active

2. **"No messages collected"**
   - Bot must be added to the group BEFORE messages are sent
   - Bot needs message reading permissions
   - Check if bot is still in the group

3. **"Rate limit exceeded"**
   - Reduce poll frequency
   - Implement longer delays between requests
   - Bot API allows ~30 requests/second

4. **"Chat not found"**
   - Verify chat ID is correct (often negative for groups)
   - Bot must be a member of the group
   - Group might be private or restricted

### Debug Mode

Enable detailed logging by setting log level:

```elixir
Logger.configure(level: :debug)
```

## Security Considerations

- Keep bot token secure and never commit it to version control
- Bot can only read messages, not send (unless additional permissions)
- Consider data privacy when exporting chat history
- Respect group member privacy and chat rules

## Performance Notes

- Telegram Bot API has rate limits
- Large message collections may take time
- JSON files can become large with many messages
- Consider using streaming for very large datasets

## Contributing

This is a proof-of-concept implementation. For production use, consider:
- Better error handling and recovery
- Database storage instead of JSON files
- Real-time streaming capabilities
- Web interface for easier management
- Enhanced search and filtering options