# PLANNING.md - Sammelkarten Project Architecture & Planning

## 🎯 Vision

### Project Mission
Create a beautiful, minimalistic web application that transforms collectible card trading into an engaging, cryptocurrency-style experience. Sammelkarten presents collectible cards as tradeable assets with real-time price tracking, historical charts, and detailed analytics.

### Core Values
- **Simplicity**: Clean, intuitive interface that focuses on essential information
- **Performance**: Lightning-fast real-time updates using Phoenix LiveView
- **Scalability**: Built to handle growing card collections and user base
- **Authenticity**: Showcase genuine collectible card data and imagery

### Target Users
- Collectible card enthusiasts and traders
- Investment-minded collectors tracking portfolio value
- Data-driven users who appreciate clean analytics interfaces
- Anyone seeking a modern approach to card collection management

## 🏗️ Architecture

### System Architecture Overview
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Frontend      │    │   Backend       │    │   Storage       │
│                 │    │                 │    │                 │
│ Phoenix LiveView│◄──►│ Elixir/Phoenix  │◄──►│ Mnesia/DETS     │
│ - Card List     │    │ - Real-time     │    │ - Card Data     │
│ - Detail Views  │    │ - Price Engine  │    │ - Price History │
│ - Price Charts  │    │ - WebSocket     │    │ - User Sessions │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Component Architecture

#### 1. Frontend Layer (Phoenix LiveView)
- **Card Dashboard**: Main interface displaying all cards with prices
- **Card Detail Page**: Individual card view with comprehensive data
- **Price Charts**: Interactive historical price visualization
- **Search & Filter**: Real-time card discovery functionality

#### 2. Backend Layer (Elixir/Phoenix)
- **Price Engine**: Core logic for price calculations and updates
- **Real-time Updates**: WebSocket connections for live data
- **API Layer**: RESTful endpoints for external integrations
- **Background Jobs**: Automated price updates and data processing

#### 3. Data Layer (Mnesia with DETS)
- **Card Records**: Card metadata, images, and current prices
- **Price History**: Time-series data for trend analysis
- **User Sessions**: LiveView state management
- **Configuration**: Application settings and parameters

### Data Models

#### Card Schema
```elixir
%Card{
  id: string(),
  name: string(),
  image_path: string(),
  current_price: decimal(),
  price_change_24h: decimal(),
  price_change_percentage: float(),
  rarity: string(),
  description: text(),
  last_updated: datetime()
}
```

#### Price History Schema
```elixir
%PriceHistory{
  id: string(),
  card_id: string(),
  price: decimal(),
  timestamp: datetime(),
  volume: integer()
}
```

## 🛠️ Technology Stack

### Core Technologies
- **Language**: Elixir 1.16+
- **Framework**: Phoenix 1.7+
- **Frontend**: Phoenix LiveView 0.20+
- **Database**: Mnesia with DETS backend
- **Build Tool**: Mix
- **Package Manager**: Hex

### Frontend Technologies
- **Styling**: Tailwind CSS 3.0+
- **Charts**: Chart.js or D3.js via JavaScript hooks
- **Icons**: Heroicons or Lucide
- **Animations**: CSS transitions and LiveView animations
- **Image Optimization**: Phoenix built-in asset pipeline

### Development Tools
- **Code Quality**: Credo, Dialyzer
- **Testing**: ExUnit, Phoenix LiveView Test Helpers
- **Formatting**: Elixir Formatter
- **Documentation**: ExDoc
- **Hot Reloading**: Phoenix Live Reload

### Deployment & Infrastructure
- **Runtime**: Erlang/OTP 26+
- **Process Management**: Elixir Supervisors
- **Monitoring**: Phoenix LiveDashboard
- **Logging**: Elixir Logger
- **Configuration**: Application environment

## 🔧 Required Tools List

### Development Environment
```bash
# Core Requirements
elixir >= 1.15.0
erlang >= 26.0
phoenix >= 1.7.0
node.js >= 18.0 (for asset pipeline)
```

### System Dependencies
```bash
# Package managers
hex
mix
npm/yarn

# Development tools
git
make (optional)
docker (optional for deployment)
```

### IDE/Editor Setup
- **VS Code Extensions**:
  - ElixirLS
  - Phoenix Framework
  - Tailwind CSS IntelliSense
- **Vim/Neovim**: elixir-ls, coc-elixir
- **Emacs**: elixir-mode, lsp-mode

### Database Tools
- **Mnesia**: Built into Erlang/OTP
- **DETS**: Built into Erlang/OTP
- **Observer**: GUI for system monitoring (`observer:start()`)

## 📊 Data Strategy

### Price Simulation Engine
Since we're dealing with collectible cards (not real trading), we need to simulate realistic price movements:

1. **Base Price Calculation**: Initial prices based on rarity and card characteristics
2. **Market Simulation**: Algorithmic price fluctuations mimicking market behavior
3. **Event-Driven Changes**: Special events affecting card values
4. **Historical Data**: Seed data for charts and trend analysis

### Real-time Updates
- **Price Refresh**: Every 30 seconds to 5 minutes
- **LiveView Updates**: Immediate UI updates via WebSocket
- **Data Persistence**: Continuous background saves to Mnesia

## 🚀 Performance Considerations

### Optimization Strategies
- **LiveView Efficiency**: Minimal DOM updates, proper component boundaries
- **Mnesia Performance**: Optimized queries and indexing
- **Image Loading**: Lazy loading and responsive images
- **Caching**: ETS tables for frequently accessed data
- **Memory Management**: Proper GenServer lifecycle management

### Scalability Planning
- **Horizontal Scaling**: Distributed Erlang capabilities
- **Load Distribution**: Multiple LiveView processes
- **Data Partitioning**: Mnesia table fragmentation if needed
- **CDN Integration**: Static asset optimization

## 🎨 Design Philosophy

### UI/UX Principles
- **Minimalism**: Clean layouts with ample whitespace
- **Hierarchy**: Clear information architecture
- **Responsiveness**: Mobile-first design approach
- **Accessibility**: WCAG 2.1 compliance
- **Performance**: Sub-100ms interactions

### Visual Design
- **Color Palette**: Professional, financial-inspired colors
- **Typography**: Clean, readable fonts (Inter, System fonts)
- **Iconography**: Consistent icon system
- **Charts**: Clean, informative data visualizations
- **Images**: High-quality card photography with consistent sizing

## 📈 Success Metrics

### Technical KPIs
- **Page Load Time**: < 1 second
- **Real-time Update Latency**: < 100ms
- **Memory Usage**: < 100MB per 1000 concurrent users
- **Database Query Time**: < 10ms average

### User Experience KPIs
- **Navigation Efficiency**: < 3 clicks to any card
- **Search Response**: < 200ms
- **Chart Interaction**: Smooth 60fps animations
- **Mobile Responsiveness**: 100% feature parity

---

*This planning document serves as the architectural foundation for the Sammelkarten project and should be referenced throughout development.*