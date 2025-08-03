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

// Chart.js hook for price history and keyboard shortcuts
let Hooks = {}

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
    this.setupInteractivity()
  },
  
  updated() {
    this.updateChart()
  },
  
  destroyed() {
    this.cleanup()
  },
  
  initChart() {
    // Initialize chart state
    this.zoom = 1.0
    this.panX = 0
    this.panY = 0
    this.isDragging = false
    this.lastMouseX = 0
    this.lastMouseY = 0
    this.minZoom = 0.5
    this.maxZoom = 5.0
    
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
  
  setupInteractivity() {
    // Mouse wheel for zooming
    this.handleWheel = (e) => {
      e.preventDefault()
      
      const rect = this.el.getBoundingClientRect()
      const mouseX = e.clientX - rect.left
      const mouseY = e.clientY - rect.top
      
      // Zoom factor
      const zoomFactor = e.deltaY > 0 ? 0.9 : 1.1
      const newZoom = Math.max(this.minZoom, Math.min(this.maxZoom, this.zoom * zoomFactor))
      
      if (newZoom !== this.zoom) {
        // Zoom towards mouse position
        const zoomRatio = newZoom / this.zoom
        this.panX = mouseX - (mouseX - this.panX) * zoomRatio
        this.panY = mouseY - (mouseY - this.panY) * zoomRatio
        this.zoom = newZoom
        
        this.updateChart()
      }
    }
    
    // Mouse drag for panning
    this.handleMouseDown = (e) => {
      this.isDragging = true
      this.lastMouseX = e.clientX
      this.lastMouseY = e.clientY
      this.el.style.cursor = 'grabbing'
    }
    
    this.handleMouseMove = (e) => {
      if (this.isDragging) {
        const deltaX = e.clientX - this.lastMouseX
        const deltaY = e.clientY - this.lastMouseY
        
        this.panX += deltaX
        this.panY += deltaY
        
        this.lastMouseX = e.clientX
        this.lastMouseY = e.clientY
        
        this.updateChart()
      }
    }
    
    this.handleMouseUp = () => {
      this.isDragging = false
      this.el.style.cursor = 'grab'
    }
    
    this.handleMouseLeave = () => {
      this.isDragging = false
      this.el.style.cursor = 'default'
    }
    
    // Double-click to reset zoom/pan
    this.handleDoubleClick = () => {
      this.zoom = 1.0
      this.panX = 0
      this.panY = 0
      this.updateChart()
    }
    
    // Touch events for mobile
    this.handleTouchStart = (e) => {
      e.preventDefault()
      if (e.touches.length === 1) {
        // Single touch - panning
        this.isDragging = true
        this.lastMouseX = e.touches[0].clientX
        this.lastMouseY = e.touches[0].clientY
      }
    }
    
    this.handleTouchMove = (e) => {
      e.preventDefault()
      if (e.touches.length === 1 && this.isDragging) {
        // Single touch - panning
        const deltaX = e.touches[0].clientX - this.lastMouseX
        const deltaY = e.touches[0].clientY - this.lastMouseY
        
        this.panX += deltaX
        this.panY += deltaY
        
        this.lastMouseX = e.touches[0].clientX
        this.lastMouseY = e.touches[0].clientY
        
        this.updateChart()
      } else if (e.touches.length === 2) {
        // Two finger pinch zoom (simplified)
        this.isDragging = false
      }
    }
    
    this.handleTouchEnd = (e) => {
      e.preventDefault()
      this.isDragging = false
    }
    
    // Add event listeners
    this.el.addEventListener('wheel', this.handleWheel)
    this.el.addEventListener('mousedown', this.handleMouseDown)
    this.el.addEventListener('mousemove', this.handleMouseMove)
    this.el.addEventListener('mouseup', this.handleMouseUp)
    this.el.addEventListener('mouseleave', this.handleMouseLeave)
    this.el.addEventListener('dblclick', this.handleDoubleClick)
    this.el.addEventListener('touchstart', this.handleTouchStart)
    this.el.addEventListener('touchmove', this.handleTouchMove)
    this.el.addEventListener('touchend', this.handleTouchEnd)
    
    // Set initial cursor
    this.el.style.cursor = 'grab'
  },
  
  cleanup() {
    if (this.handleWheel) {
      this.el.removeEventListener('wheel', this.handleWheel)
      this.el.removeEventListener('mousedown', this.handleMouseDown)
      this.el.removeEventListener('mousemove', this.handleMouseMove)
      this.el.removeEventListener('mouseup', this.handleMouseUp)
      this.el.removeEventListener('mouseleave', this.handleMouseLeave)
      this.el.removeEventListener('dblclick', this.handleDoubleClick)
      this.el.removeEventListener('touchstart', this.handleTouchStart)
      this.el.removeEventListener('touchmove', this.handleTouchMove)
      this.el.removeEventListener('touchend', this.handleTouchEnd)
    }
  },
  
  drawChart(ctx, data) {
    if (!data || data.length === 0) return
    
    const canvas = this.el
    const padding = 40
    
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
    
    // Apply zoom and pan transformations
    ctx.save()
    ctx.translate(this.panX, this.panY)
    ctx.scale(this.zoom, this.zoom)
    
    // Find min and max values
    const prices = data.map(d => d.price)
    const minPrice = Math.min(...prices)
    const maxPrice = Math.max(...prices)
    const priceRange = maxPrice - minPrice || 1
    
    // Draw background
    ctx.fillStyle = '#f9fafb'
    ctx.fillRect(-this.panX / this.zoom, -this.panY / this.zoom, rect.width / this.zoom, rect.height / this.zoom)
    
    // Draw grid lines
    ctx.strokeStyle = '#e5e7eb'
    ctx.lineWidth = 1 / this.zoom
    
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
      ctx.lineWidth = 2 / this.zoom
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
        ctx.arc(x, y, 3 / this.zoom, 0, 2 * Math.PI)
        ctx.fill()
      })
    }
    
    ctx.restore()
    
    // Draw Y-axis labels (prices) - always visible
    ctx.fillStyle = '#6b7280'
    ctx.font = '12px system-ui'
    ctx.textAlign = 'right'
    
    for (let i = 0; i <= 5; i++) {
      const price = minPrice + (priceRange / 5) * (5 - i)
      const y = padding + (chartHeight / 5) * i + 4
      ctx.fillText(`€${(price / 100).toFixed(2)}`, padding - 10, y)
    }
    
    // Draw X-axis labels (simplified - just show first and last) - always visible
    ctx.textAlign = 'center'
    if (data.length > 0) {
      const firstDate = new Date(data[data.length - 1].timestamp).toLocaleDateString()
      const lastDate = new Date(data[0].timestamp).toLocaleDateString()
      
      ctx.fillText(firstDate, padding, rect.height - 10)
      ctx.fillText(lastDate, rect.width - padding, rect.height - 10)
    }
    
    // Draw zoom indicator
    if (this.zoom !== 1.0 || this.panX !== 0 || this.panY !== 0) {
      ctx.fillStyle = 'rgba(0, 0, 0, 0.7)'
      ctx.fillRect(rect.width - 120, 10, 110, 30)
      ctx.fillStyle = '#ffffff'
      ctx.font = '10px system-ui'
      ctx.textAlign = 'left'
      ctx.fillText(`Zoom: ${this.zoom.toFixed(1)}x`, rect.width - 115, 25)
      ctx.fillText('Double-click to reset', rect.width - 115, 35)
    }
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

