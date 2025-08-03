# TASKS.md - Sammelkarten Development Tasks

## Milestone 1: Project Setup & Foundation ⚡
### Status: In Progress
- [x] Create CLAUDE.md project guide
- [x] Create PLANNING.md architecture document  
- [x] Create TASKS.md task management file
- [x] Initialize Phoenix application with LiveView
- [x] Set up project structure and dependencies
- [x] Configure Mnesia database for card storage
- [x] Set up Tailwind CSS styling framework
- [x] Create basic application layout and navigation

## Milestone 2: Core Data Models & Storage 📊
### Status: Completed ✅
- [x] Design and implement Card schema/struct
- [x] Design and implement PriceHistory schema/struct
- [x] Create Mnesia table definitions
- [x] Implement basic CRUD operations for cards
- [x] Set up card image asset pipeline
- [x] Create seed data from existing card_images/
- [x] Implement price simulation engine
- [x] Set up background job for price updates

## Milestone 3: Card Dashboard & Listing 🎯
### Status: Completed ✅
- [x] Create main dashboard LiveView page
- [x] Implement card grid/list component
- [x] Add real-time price updates via LiveView
- [x] Create search and filter functionality
- [x] Implement card sorting (price, name, change%)
- [x] Add responsive design for mobile/tablet
- [x] Style dashboard with minimalistic design
- [x] Add loading states and error handling

## Milestone 4: Individual Card Pages 🃏
### Status: Completed ✅
- [x] Create card detail LiveView page
- [x] Display comprehensive card information
- [x] Implement price history chart component
- [x] Add JavaScript hooks for chart interactivity
- [ ] Create card image gallery/viewer
- [x] Add card metadata and rarity display
- [x] Implement price change indicators
- [x] Add breadcrumb navigation

## Milestone 5: Real-time Features & Interactivity ⚡
### Status: Completed ✅
- [x] Implement WebSocket connections for live updates
- [x] Create price ticker/streaming component
- [ ] Add price alert notifications
- [x] Implement auto-refresh mechanisms
- [x] Add user preferences (refresh rates, etc.)
- [ ] Create interactive chart zooming/panning
- [x] Add keyboard shortcuts for navigation
- [x] Implement error recovery for connection issues

## Milestone 6: UI Polish & Advanced Features ✨
### Status: Pending
- [ ] Refine color scheme and typography
- [ ] Add smooth animations and transitions
- [ ] Implement dark/light theme toggle
- [ ] Add accessibility improvements (ARIA, keyboard nav)
- [ ] Create custom icons and graphics
- [ ] Add performance monitoring and optimization
- [ ] Implement lazy loading for images
- [ ] Add PWA capabilities (optional)

## Milestone 7: Testing & Quality Assurance 🧪
### Status: Pending
- [ ] Write unit tests for core business logic
- [ ] Create LiveView integration tests
- [ ] Test real-time functionality thoroughly
- [ ] Add property-based tests for price engine
- [ ] Performance testing with large datasets
- [ ] Cross-browser compatibility testing
- [ ] Mobile responsiveness testing
- [ ] Accessibility compliance verification

## Milestone 8: Deployment & Production Setup 🚀
### Status: Pending
- [ ] Set up production configuration
- [ ] Configure deployment pipeline
- [ ] Set up monitoring and logging
- [ ] Implement health checks
- [ ] Configure backup strategies for Mnesia
- [ ] Set up SSL/TLS certificates
- [ ] Performance optimization for production
- [ ] Documentation for deployment process

---

## Current Sprint Focus
**Active Milestone**: Milestone 6 - UI Polish & Advanced Features

**Next Task**: Refine color scheme and typography

## Task Management Rules
- Mark tasks as completed immediately: `[x]`
- Add new discovered tasks to appropriate milestone
- Update milestone status when starting work
- Move urgent tasks to current sprint focus
- Review and prioritize weekly

## Quick Commands
```bash
# Development
mix phx.server          # Start development server
mix test                # Run test suite
mix format              # Format code
mix credo               # Code quality check

# Database
iex -S mix              # Interactive shell
:observer.start()       # Mnesia monitoring
```

---

*Last updated: Session 2 - Phoenix setup completed*