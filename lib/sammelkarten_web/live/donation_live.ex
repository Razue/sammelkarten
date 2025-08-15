defmodule SammelkartenWeb.DonationLive do
  use SammelkartenWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Support this Project",
       lightning_address: "",
       bitcoin_address: "xxx",
       qr_code_shown: false,
       donation_type: "lightning"
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <!-- Header -->
      <div class="text-center mb-12">
        <h1 class="text-4xl font-bold text-gray-900 dark:text-white mb-4">Support Sammelkarten</h1>
        <p class="text-xl text-gray-600 dark:text-gray-300 max-w-3xl mx-auto">
          Help keep this open-source project alive and growing. Your donations support development,
          hosting, and new features for the entire community.
        </p>
      </div>
      
    <!-- Donation Options -->
      <div class="flex justify-center">
        <!-- Lightning Network -->

        <div class="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-8 text-center mb-12">
          <lightning-widget
            name="Ralph21"
            accent="#0909F9"
            to="vacantface70@walletofsatoshi.com"
            image="/images/ralph21.png"
            amounts="210,2100,21000"
          />
          <script src="https://embed.twentyuno.net/js/app.js">
          </script>
        </div>
      </div>
      
    <!-- Why Donate -->
      <div class="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-8 mb-12">
        <h2 class="text-2xl font-bold text-gray-900 dark:text-white mb-6">
          Why Support This Project?
        </h2>
        <div class="grid md:grid-cols-3 gap-8">
          <a
            href="https://github.com/razue/sammelkarten"
            target="_blank"
            rel="noopener noreferrer"
            class="group block text-center rounded-lg transition transform hover:-translate-y-1 hover:shadow-xl hover:bg-green-50 dark:hover:bg-green-900/20 focus:outline-none focus:ring-2 focus:ring-green-400"
          >
            <div class="w-16 h-16 bg-green-500 rounded-lg flex items-center justify-center mx-auto mb-4 group-hover:bg-green-600 transition-colors">
              <svg class="w-8 h-8 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4"
                />
              </svg>
            </div>
            <h3 class="text-lg font-bold text-gray-900 dark:text-white mb-2 group-hover:text-green-700 dark:group-hover:text-green-400 transition-colors">
              Open Source
            </h3>
            <p class="text-gray-600 dark:text-gray-300 group-hover:text-green-800 dark:group-hover:text-green-300 transition-colors">
              Completely open source and free for everyone to use, modify, and learn from.
            </p>
          </a>

          <a
            href="https://github.com/razue/sammelkarten/blob/master/PLANNING.md"
            target="_blank"
            rel="noopener noreferrer"
            class="group block text-center rounded-lg transition transform hover:-translate-y-1 hover:shadow-xl hover:bg-purple-50 dark:hover:bg-purple-900/20 focus:outline-none focus:ring-2 focus:ring-purple-400"
          >
            <div class="w-16 h-16 bg-purple-500 rounded-lg flex items-center justify-center mx-auto mb-4 group-hover:bg-purple-600 transition-colors">
              <svg class="w-8 h-8 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M13 10V3L4 14h7v7l9-11h-7z"
                />
              </svg>
            </div>
            <h3 class="text-lg font-bold text-gray-900 dark:text-white mb-2 group-hover:text-purple-700 dark:group-hover:text-purple-400 transition-colors">
              Modern Tech
            </h3>
            <p class="text-gray-600 dark:text-gray-300 group-hover:text-purple-800 dark:group-hover:text-purple-300 transition-colors">
              Built with cutting-edge Phoenix LiveView technology for real-time updates.
            </p>
          </a>

          <a
            href="https://github.com/razue/sammelkarten/discussions"
            target="_blank"
            rel="noopener noreferrer"
            class="group block text-center rounded-lg transition transform hover:-translate-y-1 hover:shadow-xl hover:bg-orange-50 dark:hover:bg-orange-900/20 focus:outline-none focus:ring-2 focus:ring-orange-400"
          >
            <div class="w-16 h-16 bg-orange-500 rounded-lg flex items-center justify-center mx-auto mb-4 group-hover:bg-orange-600 transition-colors">
              <svg class="w-8 h-8 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z"
                />
              </svg>
            </div>
            <h3 class="text-lg font-bold text-gray-900 dark:text-white mb-2 group-hover:text-orange-700 dark:group-hover:text-orange-400 transition-colors">
              Community Driven
            </h3>
            <p class="text-gray-600 dark:text-gray-300 group-hover:text-orange-800 dark:group-hover:text-orange-300 transition-colors">
              Your support helps maintain and improve the platform for all users.
            </p>
          </a>
        </div>
      </div>
      
    <!-- Developer Info -->
      <div class="bg-gradient-to-r from-blue-50 to-purple-50 dark:from-blue-900/20 dark:to-purple-900/20 rounded-lg p-8 text-center">
        <h2 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">About the Developer</h2>
        <p class="text-gray-700 dark:text-gray-300 max-w-2xl mx-auto mb-6">
          Hi! I'm passionate about creating beautiful, functional applications that serve the Bitcoin and collectibles community.
          This project represents countless hours of development, testing, and refinement to create something fun and perhaps useful.
        </p>
        <div class="flex justify-center space-x-4">
          <span class="bg-white dark:bg-gray-700 px-4 py-2 rounded-lg text-sm font-medium text-gray-700 dark:text-gray-300">
            Elixir Enthusiast
          </span>
          <span class="bg-white dark:bg-gray-700 px-4 py-2 rounded-lg text-sm font-medium text-gray-700 dark:text-gray-300">
            Bitcoin Advocate
          </span>
          <span class="bg-white dark:bg-gray-700 px-4 py-2 rounded-lg text-sm font-medium text-gray-700 dark:text-gray-300">
            Open Source Contributor
          </span>
        </div>
      </div>
    </div>
    """
  end
end
