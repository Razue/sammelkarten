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
### Status: Pending
- [ ] Design and implement Card schema/struct
- [ ] Design and implement PriceHistory schema/struct
- [ ] Create Mnesia table definitions
- [ ] Implement basic CRUD operations for cards
- [ ] Set up card image asset pipeline
- [ ] Create seed data from existing card_images/
- [ ] Implement price simulation engine
- [ ] Set up background job for price updates

## Milestone 3: Card Dashboard & Listing 🎯
### Status: Pending
- [ ] Create main dashboard LiveView page
- [ ] Implement card grid/list component
- [ ] Add real-time price updates via LiveView
- [ ] Create search and filter functionality
- [ ] Implement card sorting (price, name, change%)
- [ ] Add responsive design for mobile/tablet
- [ ] Style dashboard with minimalistic design
- [ ] Add loading states and error handling

## Milestone 4: Individual Card Pages 🃏
### Status: Pending
- [ ] Create card detail LiveView page
- [ ] Display comprehensive card information
- [ ] Implement price history chart component
- [ ] Add JavaScript hooks for chart interactivity
- [ ] Create card image gallery/viewer
- [ ] Add card metadata and rarity display
- [ ] Implement price change indicators
- [ ] Add breadcrumb navigation

## Milestone 5: Real-time Features & Interactivity ⚡
### Status: Pending
- [ ] Implement WebSocket connections for live updates
- [ ] Create price ticker/streaming component
- [ ] Add price alert notifications
- [ ] Implement auto-refresh mechanisms
- [ ] Add user preferences (refresh rates, etc.)
- [ ] Create interactive chart zooming/panning
- [ ] Add keyboard shortcuts for navigation
- [ ] Implement error recovery for connection issues

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
**Active Milestone**: Milestone 1 - Project Setup & Foundation

**Next Task**: Configure Mnesia database for card storage

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