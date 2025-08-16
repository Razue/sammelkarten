/**
 * Nostr JavaScript hooks for NIP-07 browser extension integration.
 * 
 * This module provides hooks for:
 * - Detecting Nostr browser extensions (Alby, nos2x, etc.)
 * - Authenticating users via NIP-07
 * - Signing events with browser extensions
 * - Managing user sessions
 */

export const NostrAuth = {
  mounted() {
    console.log("NostrAuth hook mounted");
    
    // Store reference to LiveView component
    this.liveView = this;
    
    // Check for Nostr extension on mount
    this.checkNostrSupport();
    
    // Listen for auth events
    this.handleEvent("nostr_login", (data) => {
      this.initiateLogin(data);
    });
    
    this.handleEvent("nostr_logout", () => {
      this.logout();
    });
    
    this.handleEvent("sign_event", (data) => {
      this.signEvent(data);
    });
    
    this.handleEvent("create_nostr_session", (data) => {
      this.createSession(data);
    });
  },
  
  /**
   * Check if Nostr is supported via browser extension
   */
  checkNostrSupport() {
    const hasNostr = typeof window.nostr !== 'undefined';
    
    this.pushEvent("nostr_support_status", { 
      supported: hasNostr,
      extensions: this.detectExtensions()
    });
    
    if (hasNostr) {
      console.log("Nostr extension detected");
      this.getPublicKey();
    } else {
      console.log("No Nostr extension found");
    }
  },
  
  /**
   * Detect specific Nostr extensions
   */
  detectExtensions() {
    const extensions = [];
    
    // Check for common extensions
    if (window.nostr) {
      // Try to detect specific extensions by their unique properties
      if (window.webln) {
        extensions.push("Alby");
      }
      if (window.nostr.nos2x) {
        extensions.push("nos2x");
      }
      if (window.nostr.flamingo) {
        extensions.push("Flamingo");
      }
      
      // Generic detection if no specific extension found
      if (extensions.length === 0) {
        extensions.push("Unknown Nostr Extension");
      }
    }
    
    return extensions;
  },
  
  /**
   * Get user's public key from extension
   */
  async getPublicKey() {
    try {
      const pubkey = await window.nostr.getPublicKey();
      console.log("Got public key:", pubkey);
      
      this.pushEvent("nostr_pubkey_received", { pubkey });
    } catch (error) {
      console.error("Error getting public key:", error);
      this.pushEvent("nostr_error", { 
        error: "Failed to get public key", 
        details: error.message 
      });
    }
  },
  
  /**
   * Initiate login process
   */
  async initiateLogin(data) {
    const { challenge, relay_url } = data;
    
    try {
      // First get the public key
      const pubkey = await window.nostr.getPublicKey();
      
      // Create the authentication event
      const authEvent = {
        kind: 22242,
        pubkey: pubkey,
        created_at: Math.floor(Date.now() / 1000),
        tags: [
          ["challenge", challenge]
        ],
        content: ""
      };
      
      // Add relay tag if provided
      if (relay_url) {
        authEvent.tags.push(["relay", relay_url]);
      }
      
      console.log("Signing auth event:", authEvent);
      
      // Sign the event
      const signedEvent = await window.nostr.signEvent(authEvent);
      
      console.log("Signed auth event:", signedEvent);
      
      // Send back to LiveView
      this.pushEvent("nostr_auth_signed", { 
        signed_event: signedEvent,
        challenge: challenge
      });
      
    } catch (error) {
      console.error("Login error:", error);
      this.pushEvent("nostr_error", { 
        error: "Login failed", 
        details: error.message 
      });
    }
  },
  
  /**
   * Sign a generic event
   */
  async signEvent(data) {
    const { event, callback_event } = data;
    
    try {
      console.log("Signing event:", event);
      
      const signedEvent = await window.nostr.signEvent(event);
      
      console.log("Event signed:", signedEvent);
      
      // Send back to LiveView with callback event name
      this.pushEvent(callback_event || "event_signed", { 
        signed_event: signedEvent,
        original_event: event
      });
      
    } catch (error) {
      console.error("Signing error:", error);
      this.pushEvent("nostr_error", { 
        error: "Failed to sign event", 
        details: error.message 
      });
    }
  },
  
  /**
   * Encrypt a message (NIP-04)
   */
  async encryptMessage(data) {
    const { pubkey, message } = data;
    
    try {
      const encrypted = await window.nostr.nip04.encrypt(pubkey, message);
      
      this.pushEvent("message_encrypted", {
        encrypted_message: encrypted,
        recipient_pubkey: pubkey
      });
      
    } catch (error) {
      console.error("Encryption error:", error);
      this.pushEvent("nostr_error", { 
        error: "Failed to encrypt message", 
        details: error.message 
      });
    }
  },
  
  /**
   * Decrypt a message (NIP-04)
   */
  async decryptMessage(data) {
    const { pubkey, encrypted_message } = data;
    
    try {
      const decrypted = await window.nostr.nip04.decrypt(pubkey, encrypted_message);
      
      this.pushEvent("message_decrypted", {
        decrypted_message: decrypted,
        sender_pubkey: pubkey
      });
      
    } catch (error) {
      console.error("Decryption error:", error);
      this.pushEvent("nostr_error", { 
        error: "Failed to decrypt message", 
        details: error.message 
      });
    }
  },
  
  /**
   * Create a Nostr session by posting to the session controller
   */
  async createSession(data) {
    console.log("Creating Nostr session", data);
    
    try {
      // Get CSRF token from meta tag
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
      
      const response = await fetch('/nostr/session', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken
        },
        body: JSON.stringify(data)
      });
      
      if (response.ok) {
        console.log("Session created successfully");
        // Store session data locally for faster access
        this.storeSession(data.user);
        
        // Redirect to portfolio page
        window.location.href = '/portfolio';
      } else {
        console.error("Failed to create session", response);
        this.pushEvent("nostr_error", { 
          error: "Failed to create session", 
          details: `HTTP ${response.status}` 
        });
      }
    } catch (error) {
      console.error("Session creation error:", error);
      this.pushEvent("nostr_error", { 
        error: "Failed to create session", 
        details: error.message 
      });
    }
  },

  /**
   * Logout user
   */
  logout() {
    console.log("Logging out user");
    
    // Make DELETE request to session controller
    this.deleteSession();
    
    // Clear any local storage
    localStorage.removeItem('nostr_session');
    
    this.pushEvent("nostr_logged_out", {});
  },
  
  /**
   * Delete session via controller
   */
  async deleteSession() {
    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
      
      const response = await fetch('/nostr/session', {
        method: 'DELETE',
        headers: {
          'X-CSRF-Token': csrfToken
        }
      });
      
      if (response.ok) {
        console.log("Session deleted successfully");
      } else {
        console.error("Failed to delete session", response);
      }
    } catch (error) {
      console.error("Session deletion error:", error);
    }
  },
  
  /**
   * Store session data locally
   */
  storeSession(data) {
    localStorage.setItem('nostr_session', JSON.stringify(data));
  },
  
  /**
   * Get stored session data
   */
  getStoredSession() {
    const stored = localStorage.getItem('nostr_session');
    return stored ? JSON.parse(stored) : null;
  },
  
  /**
   * Clear stored session
   */
  clearSession() {
    localStorage.removeItem('nostr_session');
  }
};

/**
 * Nostr Profile Management Hook
 */
export const NostrProfile = {
  mounted() {
    console.log("NostrProfile hook mounted");
    
    this.handleEvent("update_profile", (data) => {
      this.updateProfile(data);
    });
    
    this.handleEvent("get_profile", () => {
      this.getProfile();
    });
  },
  
  /**
   * Update user profile metadata
   */
  async updateProfile(profileData) {
    try {
      const pubkey = await window.nostr.getPublicKey();
      
      const metadataEvent = {
        kind: 0,
        pubkey: pubkey,
        created_at: Math.floor(Date.now() / 1000),
        tags: [],
        content: JSON.stringify(profileData)
      };
      
      const signedEvent = await window.nostr.signEvent(metadataEvent);
      
      this.pushEvent("profile_updated", { 
        signed_event: signedEvent 
      });
      
    } catch (error) {
      console.error("Profile update error:", error);
      this.pushEvent("nostr_error", { 
        error: "Failed to update profile", 
        details: error.message 
      });
    }
  },
  
  /**
   * Get current profile data
   */
  async getProfile() {
    try {
      const pubkey = await window.nostr.getPublicKey();
      
      this.pushEvent("profile_requested", { pubkey });
      
    } catch (error) {
      console.error("Get profile error:", error);
      this.pushEvent("nostr_error", { 
        error: "Failed to get profile", 
        details: error.message 
      });
    }
  }
};

/**
 * Trading Hook for Nostr-based card trading
 */
export const NostrTrading = {
  mounted() {
    console.log("NostrTrading hook mounted");
    
    this.handleEvent("create_trade_offer", (data) => {
      this.createTradeOffer(data);
    });
    
    this.handleEvent("accept_trade", (data) => {
      this.acceptTrade(data);
    });
  },
  
  /**
   * Create a trade offer event
   */
  async createTradeOffer(offerData) {
    try {
      const pubkey = await window.nostr.getPublicKey();
      
      const tradeEvent = {
        kind: 32122, // Custom trade offer kind
        pubkey: pubkey,
        created_at: Math.floor(Date.now() / 1000),
        tags: [
          ["d", `trade_${offerData.card_id}_${Date.now()}`],
          ["card", offerData.card_id],
          ["type", offerData.offer_type],
          ["price", offerData.price.toString()],
          ["expires", offerData.expires_at.toString()]
        ],
        content: JSON.stringify(offerData)
      };
      
      const signedEvent = await window.nostr.signEvent(tradeEvent);
      
      this.pushEvent("trade_offer_created", { 
        signed_event: signedEvent 
      });
      
    } catch (error) {
      console.error("Trade offer error:", error);
      this.pushEvent("nostr_error", { 
        error: "Failed to create trade offer", 
        details: error.message 
      });
    }
  },
  
  /**
   * Accept a trade offer
   */
  async acceptTrade(tradeData) {
    try {
      const pubkey = await window.nostr.getPublicKey();
      
      const acceptEvent = {
        kind: 32123, // Custom trade execution kind
        pubkey: pubkey,
        created_at: Math.floor(Date.now() / 1000),
        tags: [
          ["d", `execution_${tradeData.trade_id}`],
          ["trade", tradeData.trade_id],
          ["buyer", tradeData.buyer_pubkey],
          ["seller", tradeData.seller_pubkey],
          ["card", tradeData.card_id]
        ],
        content: JSON.stringify(tradeData)
      };
      
      const signedEvent = await window.nostr.signEvent(acceptEvent);
      
      this.pushEvent("trade_accepted", { 
        signed_event: signedEvent 
      });
      
    } catch (error) {
      console.error("Trade accept error:", error);
      this.pushEvent("nostr_error", { 
        error: "Failed to accept trade", 
        details: error.message 
      });
    }
  }
};

/**
 * Utility functions for Nostr
 */
export const NostrUtils = {
  /**
   * Convert hex pubkey to npub
   */
  hexToNpub(hex) {
    // This would require a bech32 library in JavaScript
    // For now, return hex (will be converted server-side)
    return hex;
  },
  
  /**
   * Convert npub to hex pubkey
   */
  npubToHex(npub) {
    // This would require a bech32 library in JavaScript
    // For now, return as-is (will be converted server-side)
    return npub;
  },
  
  /**
   * Validate event structure
   */
  validateEvent(event) {
    const required = ['kind', 'pubkey', 'created_at', 'tags', 'content'];
    return required.every(field => event.hasOwnProperty(field));
  },
  
  /**
   * Get current timestamp
   */
  now() {
    return Math.floor(Date.now() / 1000);
  }
};