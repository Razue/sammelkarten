# CLAUDE.md - Sammelkarten Project Guide

## Development Notes

### Code Style Guidelines
- Elixir Code style: Use always a function call when a pipeline is only one function long

### Server Status Notes
- The server is already running

## Project Overview
**Sammelkarten** is a web application built with Elixir Phoenix LiveView that displays collectible cards like cryptocurrency coins with price tracking and charts. The design is inspired by Kraken's Bitcoin price interface ( https://www.kraken.com/en-de/prices/bitcoin)but with a clean, minimalistic aesthetic.

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

###  Task Management
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

### Session 2 - Phoenix Foundation Setup
- Verified Phoenix application with LiveView is properly initialized
- Confirmed all dependencies including Tailwind CSS are installed
- Successfully set up asset pipeline (Tailwind and esbuild)
- Completed Milestone 1 foundation tasks except Mnesia configuration
- Added tidewave MCP tool dependency for Elixir development support

### Session 3 - Database Configuration & Layout Implementation
- Successfully configured Mnesia database with Card and PriceHistory schemas
- Created Database module for initialization and table management
- Implemented Cards context module for database operations
- Added Decimal dependency for precise price calculations
- Built complete application layout with navigation and footer
- Created placeholder pages for Cards and Market sections
- Updated routes and controllers for full navigation

**Completed Tasks:**
- ✅ Initialize Phoenix application with LiveView
- ✅ Set up project structure and dependencies  
- ✅ Set up Tailwind CSS styling framework
- ✅ Configure Mnesia database for card storage
- ✅ Create basic application layout and navigation

**Milestone 1 Status:** ✅ **COMPLETED**

**Next Priority:** Begin Milestone 3 - Card Dashboard & Listing

### Session 4 - Core Data Models & Price Engine Implementation
- Verified existing Card and PriceHistory schema implementations were well-designed
- Confirmed Mnesia database configuration and CRUD operations were functional
- Set up card image asset pipeline by copying images to `priv/static/images/cards/`
- Created comprehensive Seeds module for populating initial card data from available images
- Successfully seeded database with 8 collectible cards with realistic pricing and metadata
- Implemented sophisticated PriceEngine with market simulation features:
  - Rarity-based volatility calculations
  - Market trend influences and momentum factors
  - Random walk price movements with event-driven spikes
  - Market crash and boom simulation capabilities
- Created PriceUpdater GenServer for background price updates:
  - Automatic price updates every 2 minutes
  - PubSub integration for real-time UI notifications
  - Configurable intervals and pause/resume functionality
  - Comprehensive status monitoring and error handling
- Added PriceUpdater to application supervision tree
- Enhanced application startup with automatic database seeding

**Completed Tasks:**
- ✅ All Milestone 1 tasks (from previous sessions)
- ✅ Design and implement Card schema/struct
- ✅ Design and implement PriceHistory schema/struct  
- ✅ Create Mnesia table definitions
- ✅ Implement basic CRUD operations for cards
- ✅ Set up card image asset pipeline
- ✅ Create seed data from existing card_images/
- ✅ Implement price simulation engine
- ✅ Set up background job for price updates

**Milestone 2 Status:** ✅ **COMPLETED**

**Next Priority:** Begin Milestone 4 - Individual Card Pages

### Session 5 - Dashboard & Real-time Features Implementation
- Successfully implemented main dashboard LiveView with comprehensive functionality
- Created responsive card grid layout using Tailwind CSS breakpoints
- Implemented real-time price updates via Phoenix PubSub integration
- Added search functionality for card names and rarity filtering
- Built interactive sorting system (name, price, change percentage)
- Enhanced price formatting to handle integer storage (cents conversion)
- Fixed responsive design for mobile, tablet, and desktop layouts
- Integrated live price update indicator and clean minimalistic styling
- Updated router to use LiveView for `/cards` route
- Completed all search, filter, and sort functionality with proper state management

**Completed Tasks:**
- ✅ All Milestone 1, 2, and 3 tasks completed
- ✅ Dashboard LiveView with real-time capabilities
- ✅ Card grid component with responsive design
- ✅ Search and filter functionality
- ✅ Price sorting and percentage change indicators
- ✅ Clean, minimalistic UI following project design principles

**Milestone 3 Status:** ✅ **COMPLETED**

**Next Priority:** Begin Milestone 5 - Real-time Features & Interactivity

### Session 6 - Individual Card Pages Implementation
- Successfully implemented complete card detail LiveView pages with routing
- Created comprehensive card detail page layout with:
  - Card image display and metadata (rarity, description, last updated)
  - Real-time price information with change indicators
  - Interactive price history chart using custom Canvas implementation
  - Breadcrumb navigation back to main cards listing
  - Real-time price updates via Phoenix PubSub integration
- Built custom JavaScript hooks for chart functionality without external dependencies
- Implemented price history chart with:
  - Custom Canvas-based line chart with grid lines and labels
  - Real-time data updates when prices change
  - Responsive design supporting high DPI displays
  - Graceful handling of empty price history data
- Fixed price history query bug to handle cases with no historical data
- Added clickable navigation from dashboard cards to detail pages
- Enhanced dashboard cards with proper navigation links

**Completed Tasks:**
- ✅ All Milestone 4 tasks completed except image gallery (low priority)
- ✅ Card detail LiveView with comprehensive information display
- ✅ Custom Canvas-based price history charts with real-time updates
- ✅ JavaScript hooks for chart interactivity
- ✅ Breadcrumb navigation and price change indicators
- ✅ Real-time price update subscription for individual cards

**Milestone 4 Status:** ✅ **COMPLETED** (except optional image gallery feature)

**Next Priority:** Begin Milestone 6 - UI Polish & Advanced Features

### Session 7 - Real-time Features & Advanced Interactivity
- Successfully completed Milestone 5 - Real-time Features & Interactivity
- Enhanced dashboard with comprehensive loading states and error handling:
  - Asynchronous card loading with proper error recovery
  - Retry mechanisms for failed operations
  - Connection status indicators for WebSocket health
- Built sophisticated price ticker/streaming component:
  - Real-time horizontally scrolling ticker showing price changes
  - Custom CSS animations with smooth scrolling
  - Filters cards with significant price movements for engaging display
  - Integrates with existing PubSub system for live updates
- Implemented robust connection error recovery mechanisms:
  - Automatic reconnection attempts with exponential backoff
  - Heartbeat monitoring to detect connection issues
  - Visual connection status indicators (connected/connecting/failed/offline)
  - Graceful fallback when real-time features are unavailable
- Added comprehensive keyboard shortcuts for power users:
  - Dashboard shortcuts: S (search focus), R (refresh), 1/2/3 (sorting), H (help)
  - Card detail shortcuts: B/Escape (back to listing)
  - Interactive help modal accessible via H key
  - Proper event handling that respects input field focus
- Enhanced user experience with visual connection feedback
- Fixed template syntax issues and resolved compilation errors

**Completed Tasks:**
- ✅ All Milestone 5 tasks completed except optional features (price alerts, user preferences, chart zooming)
- ✅ Enhanced error handling and loading states throughout the application
- ✅ Real-time price ticker with smooth animations and live data updates
- ✅ Comprehensive keyboard shortcuts system with help documentation
- ✅ Connection monitoring and automatic recovery mechanisms
- ✅ Visual status indicators for real-time connection health

**Milestone 5 Status:** ✅ **COMPLETED**

**Next Priority:** Continue Milestone 6 - UI Polish & Advanced Features

### Session 8 - Market Page Implementation
- Successfully implemented complete Market LiveView replacing static HTML page
- Created comprehensive MarketLive module with real-time data integration:
  - Real-time market statistics (market cap, volume, active cards count)
  - Live top gainers and top losers sections with clickable navigation to card details
  - Interactive market overview chart with zoom/pan capabilities using Canvas
  - Time range selector (24h, 7d, 30d) with dynamic chart data updates
  - Phoenix PubSub integration for real-time price update subscriptions
- Built sophisticated MarketChart JavaScript hook with advanced interactivity:
  - Canvas-based rendering without external chart library dependencies
  - Mouse wheel zooming with zoom-to-cursor functionality
  - Click-and-drag panning for chart navigation
  - Double-click to reset zoom and pan
  - Visual indicators for zoom level and interaction hints
  - High DPI display support with proper scaling
  - Gradient area fills and smooth line charts
- Enhanced market data simulation with realistic market cap calculations
- Updated routing system to use LiveView for `/market` endpoint
- Integrated loading states and error handling throughout Market page
- Added proper navigation links from market movers to individual card detail pages

**Completed Tasks:**
- ✅ All Milestone 6 Market page implementation tasks completed
- ✅ Interactive market overview chart with zoom/pan functionality
- ✅ Real-time market statistics calculations and display
- ✅ Live top gainers/losers with database integration
- ✅ Functional time range selector affecting chart data visualization

**Market Page Features:**
- Real-time market cap aggregation based on current card prices
- Dynamic volume calculations with realistic market simulation
- Top gainers and losers updating automatically with price changes
- Interactive Canvas-based charts supporting zoom (0.5x to 3.0x) and pan operations
- Time range filtering affecting chart data points and intervals
- Clean, minimalistic design matching project aesthetic
- Mobile-responsive layout with proper loading states

**Next Priority:** Continue with remaining Milestone 6 tasks (color scheme refinement, animations, theme toggle)

### Session 9 - German Number Formatting Implementation
- Successfully implemented comprehensive German number formatting throughout the application
- Created dedicated `Sammelkarten.Formatter` module for German locale formatting:
  - Converts American decimal point format (1,234.00) to German comma format (1.234,00)
  - Handles price formatting with currency symbol (€1.234,50)
  - Supports percentage formatting with German decimal separator (+12,34%)
  - Includes thousands separator (dots) for large numbers
- Updated all number formatting functions across the codebase:
  - `Sammelkarten.Card.format_price/1` and `format_price_change/1`
  - `DashboardLive` private formatting functions
  - `MarketLive` currency and percentage formatting
  - `CardDetailLive` price and percentage formatting
  - `PriceTicker` component formatting functions
- Tested module functionality with interactive Elixir evaluation
- All price displays now show German format: €1.234,50 instead of €1,234.00
- All percentage changes now show German format: +12,34% instead of +12.34%

**Completed Tasks:**
- ✅ Created German number formatting helper module
- ✅ Updated all price formatting functions to use German decimal separator
- ✅ Updated all percentage formatting to use comma instead of period
- ✅ Applied consistent German formatting across Dashboard, Market, Card Detail, and Price Ticker
- ✅ Verified formatting works correctly through module testing

**German Formatting Examples:**
- Prices: €1.234,50 (was €1,234.50)
- Percentages: +12,34% (was +12.34%)
- Large numbers: 1.000.000,00 (was 1,000,000.00)

### Current Project Status (Session 10)
**Milestone Progress:**
- ✅ Milestones 1-5: Fully completed with all core functionality implemented
- 🔄 Milestone 6: UI Polish & Advanced Features - In Progress
  - ✅ Market page with interactive charts  
  - ✅ German number formatting throughout application
  - ✅ Admin interface with password protection
  - ⏳ Next: Color scheme and typography refinement

**Ready for:** Continue Milestone 6 UI polish tasks - theme toggle, accessibility improvements, custom icons

---

### Session 11 - Typography & Color Scheme Refinement
**Completed**: Professional typography system and enhanced color palette implementation
- **Typography System**: Implemented comprehensive typography scale with Inter font
  - Added display, heading, body, and label text classes with proper line heights and letter spacing
  - Applied consistent typography hierarchy across Dashboard, Market, and Card detail pages
  - Enhanced readability with professional font weights and spacing
- **Color Palette Enhancement**: Refined color system with better visual hierarchy
  - Created custom CSS variables for consistent primary, secondary, success, error colors
  - Implemented subtle gradient backgrounds and enhanced card styling
  - Added professional card hover effects with depth and shadow improvements
  - Enhanced navigation with gradient underlines and smooth transitions
- **Accessibility Improvements**: Enhanced focus states and contrast ratios
  - Added enhanced focus styles with ring effects and proper contrast
  - Improved status indicator colors for better accessibility
  - Applied backdrop blur effects for modern glassmorphism aesthetic
- **Component Refinements**: Updated button styles, input fields, and layout spacing
  - Created `.btn-primary`, `.btn-secondary`, `.input-professional` component classes
  - Applied new `.card-professional` styling throughout the application
  - Enhanced mobile responsiveness and interaction feedback

**Files Modified**:
- `assets/css/app.css` - Major typography and color system overhaul
- `lib/sammelkarten_web/live/dashboard_live.html.heex` - Applied new typography classes
- `lib/sammelkarten_web/live/market_live.html.heex` - Updated with enhanced styling
- `lib/sammelkarten_web/components/layouts/app.html.heex` - Navigation typography improvements
- `TASKS.md` - Marked typography and color scheme task as completed

**Visual Improvements Achieved**:
- Professional Inter font with optimized rendering
- Consistent typography scale from display to label sizes
- Enhanced color contrast and accessibility compliance
- Modern glassmorphism effects with subtle gradients
- Improved card hover interactions and visual depth
- Polished navigation with gradient accent lines

---

*Last updated: Session 11 - Typography and color scheme refinement completed*