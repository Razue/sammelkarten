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

// Chart.js hook for price history
let Hooks = {}

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
    const width = canvas.width
    const height = canvas.height
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
    
    // Find min and max values
    const prices = data.map(d => d.price)
    const minPrice = Math.min(...prices)
    const maxPrice = Math.max(...prices)
    const priceRange = maxPrice - minPrice || 1
    
    // Draw background
    ctx.fillStyle = '#f9fafb'
    ctx.fillRect(0, 0, rect.width, rect.height)
    
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
      ctx.fillText(`€${(price / 100).toFixed(2)}`, padding - 10, y)
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

