# CLAUDE.md - Sammelkarten Project Guide

## Project Overview
**Sammelkarten** is a web application built with Elixir Phoenix LiveView that displays collectible cards like cryptocurrency coins with price tracking and charts. The design is inspired by Kraken's Bitcoin price interface but with a clean, minimalistic aesthetic.

### Key Features
- Collectible card price tracking with real-time updates
- Individual card detail pages with comprehensive information
- Price history charts and trend analysis
- Clean, minimalistic UI design
- Card rarity and metadata display
- Image gallery using existing card_images/ directory

### Technology Stack
- **Backend**: Elixir Phoenix Framework
- **Frontend**: Phoenix LiveView for real-time updates
- **Database**: Mnesia with DETS backend
- **Styling**: Modern CSS with minimalistic design
- **Assets**: Card images stored in card_images/ directory

## Session Workflow

### Starting a New Session
Always begin new Claude Code sessions with:

```
Please read PLANNING.md, CLAUDE.md, and TASKS.md to understand the project. Then complete the first task from TASKS.md.
```

### Continuing Previous Work
For ongoing sessions:

```
Please check PLANNING.md, CLAUDE.md, and TASKS.md to see where we are in the project. Then pick up where we left off completing the last task or continue with the next task.
```

### Before Ending a Session
Add a summary to CLAUDE.md:

```
Please add a session summary to CLAUDE.md summarizing what we've done so far.
```

## Essential Session Rules

### =� Mandatory File Reading
- **ALWAYS** read PLANNING.md at the start of every new conversation
- **CHECK** TASKS.md before starting any work
- **REVIEW** this CLAUDE.md file for project context

###  Task Management
- **MARK** completed tasks in TASKS.md immediately upon completion
- **ADD** newly discovered tasks to TASKS.md when found
- **UPDATE** task status in real-time during development
- **PRIORITIZE** tasks based on project milestones

## Available Card Images
The following collectible cards are available in `card_images/`:
- BITCOIN_HOTEL.jpg
- BLOCKTRAINER.jpg
- CHRISTIAN_DECKER.jpg
- JONAS_NICK.jpg
- NODESIGNAL.jpg
- PLEBRAP.jpg
- SEED_OR_CHRIS.jpg
- TOXIC_BOOSTER.jpg

## Development Guidelines

### Design Philosophy
- **Minimalistic**: Clean, uncluttered interface
- **Intuitive**: Easy navigation and card discovery
- **Responsive**: Works seamlessly on all devices
- **Fast**: Leverages LiveView for real-time updates

### Code Standards
- Follow Elixir and Phoenix conventions
- Use LiveView for interactive components
- Implement proper error handling
- Write clear, documented code
- Maintain consistent naming patterns

### MCP Tools Available
Elixir/Phoenix specific tools:
- `mcp__tidewave__project_eval` - Evaluate Elixir code
- `mcp__tidewave__execute_sql_query` - Run SQL queries
- `mcp__tidewave__get_ecto_schemas` - List Ecto schemas
- `mcp__tidewave__get_source_location` - Find module source
- `mcp__tidewave__get_package_location` - Find dependency locations
- `mcp__tidewave__get_logs` - View application logs
- `mcp__tidewave__list_liveview_pages` - List active LiveViews
- `mcp__tidewave__package_search` - Search Hex packages
- `mcp__tidewave__package_docs_search` - Search package docs

## Project Commands

### Testing
```bash
mix test
```

### Running the Application
```bash
mix phx.server
```

## Architecture Notes

### Core Components
1. **Card Model** - Represents collectible cards with price data
2. **Price Tracking** - Historical price storage and trend calculation
3. **LiveView Pages** - Real-time card listing and detail views
4. **Chart Components** - Price visualization using chart libraries
5. **Image Management** - Efficient loading and display of card images

### Database Schema (Planned)
- Cards table with metadata, pricing, and rarity
- Price history table for trend tracking
- User interactions and favorites (future feature)

## Session History

### Session 1 - Project Initialization
- Created initial project structure
- Set up CLAUDE.md, PLANNING.md, and TASKS.md files
- Identified card images and project requirements
- Established development workflow and session management

---

*Last updated: Session 1 - Project setup and documentation*