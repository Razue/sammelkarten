defmodule Sammelkarten.Nostr.Relay.Storage do
  @moduledoc """
  SQLite-based storage for Nostr relay events.
  
  Handles:
  - Event persistence with indexes
  - Query filtering by kind, pubkey, tags
  - Parameterized replaceable event handling
  - Event counting for COUNT requests
  """
  
  use GenServer
  require Logger
  
  alias Sammelkarten.Nostr.Event
  
  defstruct [:db_path, :conn]
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(opts) do
    db_path = Keyword.get(opts, :db_path, "priv/nostr_relay.db")
    File.mkdir_p!(Path.dirname(db_path))
    
    {:ok, conn} = Exqlite.Sqlite3.open(db_path)
    
    :ok = create_tables(conn)
    :ok = create_indexes(conn)
    
    state = %__MODULE__{db_path: db_path, conn: conn}
    Logger.info("Relay storage initialized: #{db_path}")
    
    {:ok, state}
  end
  
  def store_event(pid \\ __MODULE__, event) do
    GenServer.call(pid, {:store_event, event})
  end
  
  def query_events(pid \\ __MODULE__, filters) do
    GenServer.call(pid, {:query_events, filters})
  end
  
  def count_events(pid \\ __MODULE__, filters) do
    GenServer.call(pid, {:count_events, filters})
  end
  
  @impl true
  def handle_call({:store_event, event}, _from, state) do
    result = insert_event(state.conn, event)
    {:reply, result, state}
  end
  
  def handle_call({:query_events, filters}, _from, state) do
    events = select_events(state.conn, filters)
    {:reply, events, state}
  end
  
  def handle_call({:count_events, filters}, _from, state) do
    count = count_filtered_events(state.conn, filters)
    {:reply, count, state}
  end
  
  @impl true
  def terminate(_reason, state) do
    if state.conn do
      Exqlite.Sqlite3.close(state.conn)
    end
  end
  
  # Database operations
  
  defp create_tables(conn) do
    # Main events table
    events_sql = """
    CREATE TABLE IF NOT EXISTS events (
      id TEXT PRIMARY KEY,
      pubkey TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      kind INTEGER NOT NULL,
      tags TEXT NOT NULL,
      content TEXT NOT NULL,
      sig TEXT NOT NULL,
      indexed_at INTEGER DEFAULT (strftime('%s', 'now'))
    )
    """
    
    # Tags table for efficient filtering
    tags_sql = """
    CREATE TABLE IF NOT EXISTS event_tags (
      event_id TEXT NOT NULL,
      tag_name TEXT NOT NULL,
      tag_value TEXT,
      tag_index INTEGER NOT NULL,
      FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE
    )
    """
    
    :ok = Exqlite.Sqlite3.execute(conn, events_sql)
    :ok = Exqlite.Sqlite3.execute(conn, tags_sql)
    :ok
  end
  
  defp create_indexes(conn) do
    indexes = [
      "CREATE INDEX IF NOT EXISTS idx_events_pubkey ON events(pubkey)",
      "CREATE INDEX IF NOT EXISTS idx_events_kind ON events(kind)",
      "CREATE INDEX IF NOT EXISTS idx_events_created_at ON events(created_at)",
      "CREATE INDEX IF NOT EXISTS idx_events_kind_pubkey ON events(kind, pubkey)",
      "CREATE INDEX IF NOT EXISTS idx_tags_name_value ON event_tags(tag_name, tag_value)",
      "CREATE INDEX IF NOT EXISTS idx_tags_event_id ON event_tags(event_id)"
    ]
    
    for index_sql <- indexes do
      :ok = Exqlite.Sqlite3.execute(conn, index_sql)
    end
    :ok
  end
  
  defp insert_event(conn, event) do
    # Handle parameterized replaceable events (kinds 30000-39999)
    if parameterized_replaceable?(event.kind) do
      handle_replaceable_event(conn, event)
    else
      insert_new_event(conn, event)
    end
  end
  
  defp parameterized_replaceable?(kind) do
    kind >= 30000 and kind <= 39999
  end
  
  defp handle_replaceable_event(conn, event) do
    d_tag = find_d_tag(event.tags)
    
    if d_tag do
      # Delete existing event with same kind, pubkey, and d tag
      delete_sql = """
      DELETE FROM events WHERE kind = ? AND pubkey = ? AND id IN (
        SELECT DISTINCT event_id FROM event_tags 
        WHERE tag_name = 'd' AND tag_value = ?
      )
      """
      
      {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, delete_sql)
      :ok = Exqlite.Sqlite3.bind(stmt, [event.kind, event.pubkey, d_tag])
      :done = Exqlite.Sqlite3.step(conn, stmt)
      Exqlite.Sqlite3.release(conn, stmt)
    end
    
    insert_new_event(conn, event)
  end
  
  defp find_d_tag(tags) do
    Enum.find_value(tags, fn
      ["d", value | _] -> value
      _ -> nil
    end)
  end
  
  defp insert_new_event(conn, event) do
    # Insert main event
    event_sql = """
    INSERT INTO events (id, pubkey, created_at, kind, tags, content, sig)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    """
    
    tags_json = Jason.encode!(event.tags)
    
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, event_sql)
    
    case Exqlite.Sqlite3.bind(stmt, [
      event.id, event.pubkey, event.created_at, event.kind,
      tags_json, event.content, event.sig
    ]) do
      :ok ->
        case Exqlite.Sqlite3.step(conn, stmt) do
          :done ->
            Exqlite.Sqlite3.release(conn, stmt)
            insert_event_tags(conn, event)
            :ok
          {:error, reason} ->
            Exqlite.Sqlite3.release(conn, stmt)
            {:error, "Failed to store event: #{inspect(reason)}"}
        end
      {:error, reason} ->
        Exqlite.Sqlite3.release(conn, stmt)
        {:error, "Failed to bind event: #{inspect(reason)}"}
    end
  end
  
  defp insert_event_tags(conn, event) do
    tag_sql = "INSERT INTO event_tags (event_id, tag_name, tag_value, tag_index) VALUES (?, ?, ?, ?)"
    
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, tag_sql)
    
    event.tags
    |> Enum.with_index()
    |> Enum.each(fn {tag, index} ->
      case tag do
        [name] -> 
          :ok = Exqlite.Sqlite3.bind(stmt, [event.id, name, nil, index])
          :done = Exqlite.Sqlite3.step(conn, stmt)
          :ok = Exqlite.Sqlite3.reset(stmt)
        [name, value | _] -> 
          :ok = Exqlite.Sqlite3.bind(stmt, [event.id, name, value, index])
          :done = Exqlite.Sqlite3.step(conn, stmt)
          :ok = Exqlite.Sqlite3.reset(stmt)
        _ -> 
          :ok
      end
    end)
    
    Exqlite.Sqlite3.release(conn, stmt)
  end
  
  defp select_events(conn, filters) do
    {where_clauses, params} = build_where_clauses(filters)
    
    base_sql = """
    SELECT DISTINCT e.id, e.pubkey, e.created_at, e.kind, e.tags, e.content, e.sig
    FROM events e
    """
    
    sql = if Enum.empty?(where_clauses) do
      base_sql <> " ORDER BY e.created_at DESC"
    else
      joins = build_joins(filters)
      where_sql = Enum.join(where_clauses, " AND ")
      limit_sql = build_limit(filters)
      
      base_sql <> joins <> " WHERE " <> where_sql <> " ORDER BY e.created_at DESC" <> limit_sql
    end
    
    case Exqlite.Sqlite3.prepare(conn, sql) do
      {:ok, stmt} ->
        case Exqlite.Sqlite3.bind(stmt, params) do
          :ok ->
            {:ok, rows} = Exqlite.Sqlite3.fetch_all(conn, stmt)
            Exqlite.Sqlite3.release(conn, stmt)
            rows_to_events(rows)
          error ->
            Exqlite.Sqlite3.release(conn, stmt)
            Logger.error("Failed to bind query: #{inspect(error)}")
            []
        end
      error ->
        Logger.error("Failed to prepare query: #{inspect(error)}")
        []
    end
  end
  
  defp count_filtered_events(conn, filters) do
    {where_clauses, params} = build_where_clauses(filters)
    
    sql = if Enum.empty?(where_clauses) do
      "SELECT COUNT(*) FROM events"
    else
      joins = build_joins(filters)
      where_sql = Enum.join(where_clauses, " AND ")
      "SELECT COUNT(DISTINCT e.id) FROM events e" <> joins <> " WHERE " <> where_sql
    end
    
    case Exqlite.Sqlite3.prepare(conn, sql) do
      {:ok, stmt} ->
        case Exqlite.Sqlite3.bind(stmt, params) do
          :ok ->
            case Exqlite.Sqlite3.fetch_all(conn, stmt) do
              {:ok, [[count]]} ->
                Exqlite.Sqlite3.release(conn, stmt)
                count
              _ ->
                Exqlite.Sqlite3.release(conn, stmt)
                0
            end
          _error ->
            Exqlite.Sqlite3.release(conn, stmt)
            0
        end
      _error ->
        0
    end
  end
  
  defp build_where_clauses(filters) do
    filters
    |> Enum.with_index()
    |> Enum.flat_map(fn {filter, filter_idx} ->
      filter = Enum.into(filter, %{})
      build_filter_clauses(filter, filter_idx)
    end)
    |> Enum.unzip()
    |> then(fn {clauses, param_lists} -> {clauses, List.flatten(param_lists)} end)
  end
  
  defp build_filter_clauses(filter, filter_idx) do
    Enum.flat_map(filter, fn
      {"kinds", kinds} ->
        placeholders = List.duplicate("?", length(kinds)) |> Enum.join(", ")
        {["e.kind IN (#{placeholders})"], [kinds]}
      
      {"authors", authors} ->
        placeholders = List.duplicate("?", length(authors)) |> Enum.join(", ")
        {["e.pubkey IN (#{placeholders})"], [authors]}
      
      {"ids", ids} ->
        placeholders = List.duplicate("?", length(ids)) |> Enum.join(", ")
        {["e.id IN (#{placeholders})"], [ids]}
      
      {"#" <> tag_name, values} ->
        alias_name = "t#{filter_idx}_#{tag_name}"
        placeholders = List.duplicate("?", length(values)) |> Enum.join(", ")
        {["#{alias_name}.tag_value IN (#{placeholders})"], [values]}
      
      {"since", since} ->
        {["e.created_at >= ?"], [[since]]}
      
      {"until", until} ->
        {["e.created_at <= ?"], [[until]]}
      
      _ ->
        {[], [[]]}
    end)
  end
  
  defp build_joins(filters) do
    filters
    |> Enum.with_index()
    |> Enum.flat_map(fn {filter, filter_idx} ->
      filter = Enum.into(filter, %{})
      
      Enum.flat_map(filter, fn
        {"#" <> tag_name, _values} ->
          alias_name = "t#{filter_idx}_#{tag_name}"
          [" JOIN event_tags #{alias_name} ON e.id = #{alias_name}.event_id AND #{alias_name}.tag_name = '#{tag_name}'"]
        _ ->
          []
      end)
    end)
    |> Enum.join("")
  end
  
  defp build_limit(filters) do
    limit = filters
    |> Enum.flat_map(fn filter ->
      filter = Enum.into(filter, %{})
      case Map.get(filter, "limit") do
        nil -> []
        limit when is_integer(limit) and limit > 0 -> [limit]
        _ -> []
      end
    end)
    |> Enum.min(fn -> nil end)
    
    if limit, do: " LIMIT #{limit}", else: ""
  end
  
  defp rows_to_events(rows) do
    Enum.map(rows, fn [id, pubkey, created_at, kind, tags_json, content, sig] ->
      {:ok, tags} = Jason.decode(tags_json)
      
      %Event{
        id: id,
        pubkey: pubkey,
        created_at: created_at,
        kind: kind,
        tags: tags,
        content: content,
        sig: sig
      }
    end)
  end
end