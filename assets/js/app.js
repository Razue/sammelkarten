// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import { NostrAuth, NostrProfile, NostrTrading } from "./nostr"

// Chart.js hook for price history and keyboard shortcuts
let Hooks = {}

// Add Nostr hooks
Hooks.NostrAuth = NostrAuth
Hooks.NostrProfile = NostrProfile
Hooks.NostrTrading = NostrTrading

// Theme toggle hook for real-time theme switching
Hooks.ThemeToggle = {
  mounted() {
    // Listen for theme change events from LiveView
    this.handleEvent("theme-changed", ({theme}) => {
      this.toggleTheme(theme)
    })
  },
  
  toggleTheme(theme) {
    const htmlElement = document.documentElement
    
    if (theme === "dark") {
      htmlElement.classList.add("dark")
    } else {
      htmlElement.classList.remove("dark")
    }
    
    // Optional: Store theme preference in localStorage for persistence
    localStorage.setItem("theme", theme)
  }
}

// Price flash animation hook for real-time price updates
Hooks.PriceFlash = {
  mounted() {
    this.oldPrice = this.el.dataset.price
  },
  
  updated() {
    const newPrice = this.el.dataset.price
    const oldPrice = this.oldPrice
    
    if (oldPrice && newPrice && oldPrice !== newPrice) {
      // Determine if price went up or down
      const priceChange = parseFloat(newPrice) - parseFloat(oldPrice)
      
      // Add flash animation class
      this.el.classList.remove('price-flash-green', 'price-flash-red')
      
      if (priceChange > 0) {
        this.el.classList.add('price-flash-green')
      } else if (priceChange < 0) {
        this.el.classList.add('price-flash-red')
      }
      
      // Remove the class after animation completes
      setTimeout(() => {
        this.el.classList.remove('price-flash-green', 'price-flash-red')
      }, 600)
    }
    
    this.oldPrice = newPrice
  }
}

// Smooth page transitions
Hooks.PageTransition = {
  mounted() {
    this.el.classList.add('page-transition')
  },
  
  updated() {
    // Re-trigger page transition animation on updates
    this.el.classList.remove('page-transition')
    setTimeout(() => {
      this.el.classList.add('page-transition')
    }, 10)
  }
}

// Enhanced search functionality with animations
Hooks.SearchAnimation = {
  mounted() {
    this.searchTimeout = null
    
    // Add focus/blur animations
    this.el.addEventListener('focus', () => {
      this.el.parentElement.classList.add('search-focused')
    })
    
    this.el.addEventListener('blur', () => {
      this.el.parentElement.classList.remove('search-focused')
    })
    
    // Add typing animation feedback
    this.el.addEventListener('input', (e) => {
      // Clear existing timeout
      if (this.searchTimeout) {
        clearTimeout(this.searchTimeout)
      }
      
      // Add typing indicator
      this.el.classList.add('search-typing')
      
      // Debounce the search to reduce server load
      this.searchTimeout = setTimeout(() => {
        this.el.classList.remove('search-typing')
      }, 300)
    })
  },
  
  destroyed() {
    if (this.searchTimeout) {
      clearTimeout(this.searchTimeout)
    }
  }
}

// Smooth scrolling behavior
Hooks.SmoothScroll = {
  mounted() {
    // Add smooth scrolling to all anchor links
    const links = this.el.querySelectorAll('a[href^="#"]')
    
    links.forEach(link => {
      link.addEventListener('click', (e) => {
        e.preventDefault()
        const targetId = link.getAttribute('href').substring(1)
        const targetElement = document.getElementById(targetId)
        
        if (targetElement) {
          targetElement.scrollIntoView({
            behavior: 'smooth',
            block: 'start'
          })
        }
      })
    })
    
    // Add smooth scroll to top functionality
    this.scrollToTop = () => {
      window.scrollTo({
        top: 0,
        behavior: 'smooth'
      })
    }
  },
  
  destroyed() {
    // Cleanup if needed
  }
}

// Keyboard shortcuts hook
Hooks.KeyboardShortcuts = {
  mounted() {
    this.handleKeyDown = (e) => {
      // Only handle shortcuts when not in input fields
      if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') {
        return
      }
      
      switch(e.key.toLowerCase()) {
        case 's':
          // Focus search input
          e.preventDefault()
          const searchInput = document.querySelector('input[name="search[term]"]')
          if (searchInput) {
            searchInput.focus()
          }
          break
          
        case 'h':
        case '?':
          // Show help
          e.preventDefault()
          this.pushEvent("show_help")
          break
          
        case 'r':
          // Refresh data
          e.preventDefault()
          this.pushEvent("refresh_data")
          break
          
        case 'escape':
          // Clear search or close modals
          e.preventDefault()
          const searchInput2 = document.querySelector('input[name="search[term]"]')
          if (searchInput2 && searchInput2.value) {
            searchInput2.value = ''
            this.pushEvent("search", {search: {term: ''}})
          }
          break
          
        case '1':
        case '2':
        case '3':
          // Sort shortcuts
          e.preventDefault()
          const sortOptions = ['name', 'price', 'change']
          const sortBy = sortOptions[parseInt(e.key) - 1]
          if (sortBy) {
            this.pushEvent("sort", {sort_by: sortBy})
          }
          break
      }
    }
    
    document.addEventListener('keydown', this.handleKeyDown)
  },
  
  destroyed() {
    document.removeEventListener('keydown', this.handleKeyDown)
  }
}

// Card detail keyboard shortcuts hook
Hooks.CardDetailKeyboardShortcuts = {
  mounted() {
    this.handleKeyDown = (e) => {
      // Only handle shortcuts when not in input fields
      if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') {
        return
      }
      
      switch(e.key.toLowerCase()) {
        case 'escape':
        case 'b':
          // Go back to cards listing
          e.preventDefault()
          this.pushEvent("go_back")
          break
          
        case 'h':
        case '?':
          // Show help (could implement card-specific help)
          e.preventDefault()
          break
      }
    }
    
    document.addEventListener('keydown', this.handleKeyDown)
  },
  
  destroyed() {
    document.removeEventListener('keydown', this.handleKeyDown)
  }
}

Hooks.PriceChart = {
  mounted() {
    this.initChart()
  },
  
  updated() {
    this.updateChart()
  },
  
  initChart() {
    const ctx = this.el.getContext('2d')
    const data = JSON.parse(this.el.dataset.chartData)
    
    // Simple canvas-based chart without external dependencies
    this.drawChart(ctx, data)
  },
  
  updateChart() {
    const ctx = this.el.getContext('2d')
    const data = JSON.parse(this.el.dataset.chartData)
    
    // Clear and redraw
    ctx.clearRect(0, 0, this.el.width, this.el.height)
    this.drawChart(ctx, data)
  },
  
  drawChart(ctx, data) {
    if (!data || data.length === 0) return
    
    const canvas = this.el
    const padding = 80
    
    // Set canvas size for high DPI displays
    const rect = canvas.getBoundingClientRect()
    const dpr = window.devicePixelRatio || 1
    canvas.width = rect.width * dpr
    canvas.height = rect.height * dpr
    ctx.scale(dpr, dpr)
    canvas.style.width = rect.width + 'px'
    canvas.style.height = rect.height + 'px'
    
    const chartWidth = rect.width - (padding * 2)
    const chartHeight = rect.height - (padding * 2)
    
    // Draw background
    ctx.fillStyle = '#f9fafb'
    ctx.fillRect(0, 0, rect.width, rect.height)
    
    // Find min and max values
    const prices = data.map(d => d.price)
    const minPrice = Math.min(...prices)
    const maxPrice = Math.max(...prices)
    const priceRange = maxPrice - minPrice || 1
    
    // Draw grid lines
    ctx.strokeStyle = '#e5e7eb'
    ctx.lineWidth = 1
    
    // Horizontal grid lines
    for (let i = 0; i <= 5; i++) {
      const y = padding + (chartHeight / 5) * i
      ctx.beginPath()
      ctx.moveTo(padding, y)
      ctx.lineTo(rect.width - padding, y)
      ctx.stroke()
    }
    
    // Vertical grid lines
    for (let i = 0; i <= 4; i++) {
      const x = padding + (chartWidth / 4) * i
      ctx.beginPath()
      ctx.moveTo(x, padding)
      ctx.lineTo(x, rect.height - padding)
      ctx.stroke()
    }
    
    // Draw price line
    if (data.length > 1) {
      ctx.strokeStyle = '#3b82f6'
      ctx.lineWidth = 2
      ctx.beginPath()
      
      data.forEach((point, index) => {
        const x = padding + (chartWidth / (data.length - 1)) * index
        const y = padding + chartHeight - ((point.price - minPrice) / priceRange) * chartHeight
        
        if (index === 0) {
          ctx.moveTo(x, y)
        } else {
          ctx.lineTo(x, y)
        }
      })
      
      ctx.stroke()
      
      // Draw points
      ctx.fillStyle = '#3b82f6'
      data.forEach((point, index) => {
        const x = padding + (chartWidth / (data.length - 1)) * index
        const y = padding + chartHeight - ((point.price - minPrice) / priceRange) * chartHeight
        
        ctx.beginPath()
        ctx.arc(x, y, 3, 0, 2 * Math.PI)
        ctx.fill()
      })
    }
    
    // Draw Y-axis labels (prices)
    ctx.fillStyle = '#6b7280'
    ctx.font = '12px system-ui'
    ctx.textAlign = 'right'
    
    for (let i = 0; i <= 5; i++) {
      const price = minPrice + (priceRange / 5) * (5 - i)
      const y = padding + (chartHeight / 5) * i + 4
      ctx.fillText(`${Math.floor(price)} sats`, padding - 10, y)
    }
    
    // Draw X-axis labels (simplified - just show first and last)
    ctx.textAlign = 'center'
    if (data.length > 0) {
      const firstDate = new Date(data[data.length - 1].timestamp).toLocaleDateString()
      const lastDate = new Date(data[0].timestamp).toLocaleDateString()
      
      ctx.fillText(firstDate, padding, rect.height - 10)
      ctx.fillText(lastDate, rect.width - padding, rect.height - 10)
    }
  }
}

// Market chart hook - similar to PriceChart but optimized for market overview
Hooks.MarketChart = {
  mounted() {
    this.initChart()
  },
  
  updated() {
    this.updateChart()
  },
  
  initChart() {
    const ctx = this.el.getContext('2d')
    const data = JSON.parse(this.el.dataset.chartData)
    
    this.drawChart(ctx, data)
  },
  
  updateChart() {
    const ctx = this.el.getContext('2d')
    const data = JSON.parse(this.el.dataset.chartData)
    
    // Clear and redraw
    ctx.clearRect(0, 0, this.el.width, this.el.height)
    this.drawChart(ctx, data)
  },
  
  drawChart(ctx, data) {
    if (!data || data.length === 0) {
      // Draw empty state
      const canvas = this.el
      const rect = canvas.getBoundingClientRect()
      ctx.fillStyle = '#f3f4f6'
      ctx.fillRect(0, 0, rect.width, rect.height)
      
      ctx.fillStyle = '#6b7280'
      ctx.font = '14px system-ui'
      ctx.textAlign = 'center'
      ctx.fillText('No market data available', rect.width / 2, rect.height / 2)
      return
    }
    
    const canvas = this.el
    const padding = 60
    
    // Set canvas size for high DPI displays
    const rect = canvas.getBoundingClientRect()
    const dpr = window.devicePixelRatio || 1
    canvas.width = rect.width * dpr
    canvas.height = rect.height * dpr
    ctx.scale(dpr, dpr)
    canvas.style.width = rect.width + 'px'
    canvas.style.height = rect.height + 'px'
    
    const chartWidth = rect.width - (padding * 2)
    const chartHeight = rect.height - (padding * 2)
    
    // Find min and max values
    const values = data.map(d => d.value)
    const minValue = Math.min(...values)
    const maxValue = Math.max(...values)
    const valueRange = maxValue - minValue || 1
    
    // Draw background
    ctx.fillStyle = '#ffffff'
    ctx.fillRect(0, 0, rect.width, rect.height)
    
    // Draw grid lines
    ctx.strokeStyle = '#e5e7eb'
    ctx.lineWidth = 1
    
    // Horizontal grid lines
    for (let i = 0; i <= 4; i++) {
      const y = padding + (chartHeight / 4) * i
      ctx.beginPath()
      ctx.moveTo(padding, y)
      ctx.lineTo(rect.width - padding, y)
      ctx.stroke()
    }
    
    // Vertical grid lines
    const gridCount = Math.min(6, data.length)
    for (let i = 0; i <= gridCount; i++) {
      const x = padding + (chartWidth / gridCount) * i
      ctx.beginPath()
      ctx.moveTo(x, padding)
      ctx.lineTo(x, rect.height - padding)
      ctx.stroke()
    }
    
    // Draw area fill
    if (data.length > 1) {
      const gradient = ctx.createLinearGradient(0, padding, 0, rect.height - padding)
      gradient.addColorStop(0, 'rgba(59, 130, 246, 0.1)')
      gradient.addColorStop(1, 'rgba(59, 130, 246, 0.0)')
      
      ctx.fillStyle = gradient
      ctx.beginPath()
      
      // Start from bottom left
      const firstX = padding
      const firstY = rect.height - padding
      ctx.moveTo(firstX, firstY)
      
      // Draw to first data point
      const firstDataY = padding + chartHeight - ((data[0].value - minValue) / valueRange) * chartHeight
      ctx.lineTo(firstX, firstDataY)
      
      // Draw line through all data points
      data.forEach((point, index) => {
        const x = padding + (chartWidth / (data.length - 1)) * index
        const y = padding + chartHeight - ((point.value - minValue) / valueRange) * chartHeight
        ctx.lineTo(x, y)
      })
      
      // Close the area to bottom right
      const lastX = padding + chartWidth
      ctx.lineTo(lastX, rect.height - padding)
      ctx.lineTo(firstX, firstY)
      
      ctx.fill()
    }
    
    // Draw main line
    if (data.length > 1) {
      ctx.strokeStyle = '#3b82f6'
      ctx.lineWidth = 2
      ctx.beginPath()
      
      data.forEach((point, index) => {
        const x = padding + (chartWidth / (data.length - 1)) * index
        const y = padding + chartHeight - ((point.value - minValue) / valueRange) * chartHeight
        
        if (index === 0) {
          ctx.moveTo(x, y)
        } else {
          ctx.lineTo(x, y)
        }
      })
      
      ctx.stroke()
      
      // Draw data points
      ctx.fillStyle = '#3b82f6'
      data.forEach((point, index) => {
        const x = padding + (chartWidth / (data.length - 1)) * index
        const y = padding + chartHeight - ((point.value - minValue) / valueRange) * chartHeight
        
        ctx.beginPath()
        ctx.arc(x, y, 3, 0, 2 * Math.PI)
        ctx.fill()
      })
    }
    
    // Draw Y-axis labels (values)
    ctx.fillStyle = '#6b7280'
    ctx.font = '11px system-ui'
    ctx.textAlign = 'right'
    
    for (let i = 0; i <= 4; i++) {
      const value = minValue + (valueRange / 4) * (4 - i)
      const y = padding + (chartHeight / 4) * i + 3
      ctx.fillText(`${Math.floor(value / 1000)}k sats`, padding - 5, y)
    }
    
    // Draw time range indicator
    ctx.textAlign = 'center'
    ctx.fillStyle = '#9ca3af'
    ctx.font = '10px system-ui'
    const timeRange = this.el.dataset.timeRange || '24h'
    ctx.fillText(`Market Cap Over ${timeRange}`, rect.width / 2, rect.height - 5)
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// Global theme change handler
window.addEventListener("phx:theme-changed", (event) => {
  const theme = event.detail.theme
  const htmlElement = document.documentElement
  
  if (theme === "dark") {
    htmlElement.classList.add("dark")
  } else {
    htmlElement.classList.remove("dark")
  }
  
  // Store theme preference in localStorage for persistence
  localStorage.setItem("theme", theme)
})

// Mobile menu functionality
document.addEventListener('DOMContentLoaded', function() {
  const mobileMenuButton = document.getElementById('mobile-menu-button')
  const mobileMenu = document.getElementById('mobile-menu')
  
  if (mobileMenuButton && mobileMenu) {
    mobileMenuButton.addEventListener('click', function() {
      const isHidden = mobileMenu.classList.contains('hidden')
      
      if (isHidden) {
        mobileMenu.classList.remove('hidden')
        mobileMenuButton.setAttribute('aria-expanded', 'true')
      } else {
        mobileMenu.classList.add('hidden')
        mobileMenuButton.setAttribute('aria-expanded', 'false')
      }
    })
    
    // Close mobile menu when clicking outside
    document.addEventListener('click', function(event) {
      if (!mobileMenuButton.contains(event.target) && !mobileMenu.contains(event.target)) {
        mobileMenu.classList.add('hidden')
        mobileMenuButton.setAttribute('aria-expanded', 'false')
      }
    })
    
    // Close mobile menu when window is resized to desktop size
    window.addEventListener('resize', function() {
      if (window.innerWidth >= 768) { // md breakpoint
        mobileMenu.classList.add('hidden')
        mobileMenuButton.setAttribute('aria-expanded', 'false')
      }
    })
  }
})

