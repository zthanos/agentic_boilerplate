// apps/agent_web/assets/js/app.js

import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"

// Import accessibility hooks
import AccessibilityHooks from "./admin_accessibility_hooks"

// ----------------------------------------------------------------------------
// LiveView Hooks
// ----------------------------------------------------------------------------

const Hooks = {
  // Existing hooks
  WorkflowNodeTooltip: {
    mounted() {
      this.nodeId = this.el.dataset.nodeId;
      this.tooltip = document.getElementById(`tooltip-${this.nodeId}`);
      
      if (this.tooltip) {
        this.el.addEventListener('mouseenter', this.showTooltip.bind(this));
        this.el.addEventListener('mouseleave', this.hideTooltip.bind(this));
        this.el.addEventListener('mousemove', this.updateTooltipPosition.bind(this));
      }
    },

    destroyed() {
      if (this.tooltip) {
        this.el.removeEventListener('mouseenter', this.showTooltip.bind(this));
        this.el.removeEventListener('mouseleave', this.hideTooltip.bind(this));
        this.el.removeEventListener('mousemove', this.updateTooltipPosition.bind(this));
      }
    },

    showTooltip(event) {
      if (this.tooltip) {
        this.tooltip.classList.remove('hidden');
        this.updateTooltipPosition(event);
      }
    },

    hideTooltip() {
      if (this.tooltip) {
        this.tooltip.classList.add('hidden');
      }
    },

    updateTooltipPosition(event) {
      if (this.tooltip && !this.tooltip.classList.contains('hidden')) {
        const rect = this.el.getBoundingClientRect();
        const tooltipRect = this.tooltip.getBoundingClientRect();
        
        // Position tooltip above the node, centered
        let left = rect.left + (rect.width / 2) - (tooltipRect.width / 2);
        let top = rect.top - tooltipRect.height - 10;
        
        // Ensure tooltip stays within viewport
        const viewportWidth = window.innerWidth;
        const viewportHeight = window.innerHeight;
        
        if (left < 10) left = 10;
        if (left + tooltipRect.width > viewportWidth - 10) {
          left = viewportWidth - tooltipRect.width - 10;
        }
        
        if (top < 10) {
          // If no room above, show below
          top = rect.bottom + 10;
        }
        
        this.tooltip.style.left = `${left}px`;
        this.tooltip.style.top = `${top}px`;
      }
    }
  },

  AutoScroll: {
    mounted() {
      this.scrollToBottom();
      this.observer = new MutationObserver(() => {
        if (this.shouldAutoScroll()) {
          this.scrollToBottom();
        }
      });
      
      this.observer.observe(this.el, {
        childList: true,
        subtree: true,
        characterData: true
      });

      // Scroll on manual scroll near bottom
      this.el.addEventListener('scroll', () => {
        this.userScrolled = this.el.scrollTop < (this.el.scrollHeight - this.el.clientHeight - 100);
      });
    },

    updated() {
      if (this.shouldAutoScroll()) {
        this.scrollToBottom();
      }
    },

    destroyed() {
      if (this.observer) {
        this.observer.disconnect();
      }
    },

    scrollToBottom() {
      requestAnimationFrame(() => {
        this.el.scrollTop = this.el.scrollHeight;
        this.userScrolled = false;
      });
    },

    shouldAutoScroll() {
      // Auto scroll if user is near the bottom (within 100px) or hasn't manually scrolled up
      const threshold = 100;
      const position = this.el.scrollTop + this.el.clientHeight;
      const bottom = this.el.scrollHeight;
      return !this.userScrolled || (bottom - position < threshold);
    }
  },

  LlmSSE: {
    mounted() {
      this.reader = null
      this.decoder = new TextDecoder("utf-8")
      this.buffer = ""
      this.doneReceived = false
      this.abortController = null
      this.running = false

      // LiveView tells us to start streaming
      this.handleEvent("sse_start", async ({ url, payload }) => {
        try {
          await this.start(url, payload)
        } catch (err) {
          this.pushEvent("sse_error", {
            error: {
              message: "client_stream_start_failed",
              detail: String(err?.message || err),
            },
          })
        }
      })

      // Optional: allow server/UI to stop
      this.handleEvent("sse_stop", async () => {
        this.stop()
      })
    },

    destroyed() {
      this.stop()
    },

    stop() {
      try {
        if (this.abortController) this.abortController.abort()
      } catch (_) {
        // ignore
      }

      this.abortController = null
      this.reader = null
      this.buffer = ""
      this.doneReceived = false
      this.running = false
    },

    async start(url, payload) {
      // Stop any previous stream
      this.stop()

      this.abortController = new AbortController()
      this.running = true

      const resp = await fetch(url, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          accept: "text/event-stream",
        },
        body: JSON.stringify(payload),
        signal: this.abortController.signal,
      })

      if (!resp.ok) {
        const text = await resp.text().catch(() => "")
        this.running = false

        this.pushEvent("sse_error", {
          error: {
            message: "http_error",
            detail: `HTTP ${resp.status} ${resp.statusText} ${text}`.trim(),
          },
        })
        return
      }

      if (!resp.body) {
        this.running = false
        this.pushEvent("sse_error", {
          error: { message: "no_response_body", detail: "Response has no readable body." },
        })
        return
      }

      this.reader = resp.body.getReader()

      // Main streaming loop
      while (true) {
        const { value, done } = await this.reader.read()

        if (done) break
        if (!value) continue

        // Decode ONCE, normalize CRLF on the chunk, then append
        const chunk = this.decoder.decode(value, { stream: true })
        this.buffer += chunk.replace(/\r\n/g, "\n")

        this._drainFrames()

        // If server sent done event, we can stop reading early
        if (this.doneReceived) break
      }

      // Flush decoder tail (rare but correct)
      try {
        const tail = this.decoder.decode()
        if (tail) {
          this.buffer += tail.replace(/\r\n/g, "\n")
          this._drainFrames()
        }
      } catch (_) {
        // ignore
      }

      this.running = false
    },

    _drainFrames() {
      // SSE events are separated by a blank line
      const parts = this.buffer.split(/\n\n/)
      this.buffer = parts.pop() || ""

      for (const frame of parts) {
        const evt = this._parseFrame(frame)
        if (!evt) continue

        if (evt.type === "token") {
          this.pushEvent("sse_token", { token: evt.token })
        } else if (evt.type === "step_execution") {
          // NEW: Handle step execution events
          this.pushEvent("sse_step_execution", {
            step_name: evt.step_name,
            status: evt.status,
            timestamp: evt.timestamp,
            execution_time_ms: evt.execution_time_ms,
            error: evt.error,
            step_id: evt.step_id
          })
        } else if (evt.type === "done") {
          this.doneReceived = true
          const meta = evt.meta && Object.keys(evt.meta).length > 0 ? evt.meta : { done: true }
          this.pushEvent("sse_done", meta)
        } else if (evt.type === "clarify") {
          // NEW: Handle clarification requests
          this.doneReceived = true
          this.pushEvent("sse_clarify", {
            trace_id: evt.trace_id,
            question: evt.question
          })
        } else if (evt.type === "error") {
          this.doneReceived = true
          this.pushEvent("sse_error", { error: evt.error || { message: "unknown_error" } })
        } else if (evt.type === "ping") {
          // Server keepalive - ignore silently
          console.debug("SSE ping received")
        } else if (evt.type === "close") {
          // Stream close event - clean termination
          console.debug("SSE close received")
          this.doneReceived = true
        }
      }
    },

    _parseFrame(frame) {
      // frame is multiple lines: "event: x\n" and/or "data: y\n"
      // We support:
      // - event: token, data: {"token":"..."}
      // - event: step_execution, data: {"step_name":"...", "status":"...", "timestamp":..., ...}
      // - event: done,  data: {"run_id":"...", "trace_id":"...", ...}
      // - event: clarify, data: {"trace_id":"...", "question":"..."}
      // - event: error, data: {"error":{...}}
      // - event: ping, data: {"ts":123456}
      //
      // Also support "data: [DONE]" style (OpenAI-ish) defensively.

      const lines = frame.split("\n").filter((l) => l.trim() !== "")
      if (lines.length === 0) return null

      let eventName = null
      const dataLines = []

      for (const line of lines) {
        if (line.startsWith("event:")) {
          eventName = line.slice("event:".length).trim()
        } else if (line.startsWith("data:")) {
          dataLines.push(line.slice("data:".length).trim())
        }
      }

      const dataStr = dataLines.join("\n").trim()

      // OpenAI-ish done marker
      if (dataStr === "[DONE]") {
        return { type: "done", meta: {} }
      }

      // If no explicit event, try to infer from JSON shape
      if (!eventName) {
        const maybe = this._safeJson(dataStr)
        if (maybe?.token != null) return { type: "token", token: String(maybe.token) }
        if (maybe?.step_name != null && maybe?.status != null) return { 
          type: "step_execution", 
          step_name: maybe.step_name,
          status: maybe.status,
          timestamp: maybe.timestamp,
          execution_time_ms: maybe.execution_time_ms,
          error: maybe.error,
          step_id: maybe.step_id
        }
        if (maybe?.run_id != null) return { type: "done", meta: maybe }
        if (maybe?.question != null) return { type: "clarify", trace_id: maybe.trace_id, question: maybe.question }
        if (maybe?.error != null) return { type: "error", error: maybe.error }
        return null
      }

      if (eventName === "token") {
        const obj = this._safeJson(dataStr)
        if (!obj || obj.token == null) return null
        return { type: "token", token: String(obj.token) }
      }

      if (eventName === "step_execution") {
        // NEW: Parse step execution event
        const obj = this._safeJson(dataStr)
        if (!obj || !obj.step_name || !obj.status) return null
        return {
          type: "step_execution",
          step_name: obj.step_name,
          status: obj.status,
          timestamp: obj.timestamp,
          execution_time_ms: obj.execution_time_ms,
          error: obj.error,
          step_id: obj.step_id
        }
      }

      if (eventName === "done") {
        const obj = this._safeJson(dataStr)
        // Controller sends flat structure with run_id, trace_id, etc.
        return { type: "done", meta: obj || {} }
      }

      if (eventName === "clarify") {
        // NEW: Parse clarification event
        const obj = this._safeJson(dataStr)
        if (!obj || !obj.question) return null
        return {
          type: "clarify",
          trace_id: obj.trace_id,
          question: obj.question
        }
      }

      if (eventName === "error") {
        const obj = this._safeJson(dataStr)
        return { type: "error", error: obj?.error || { message: "unknown_error" } }
      }

      if (eventName === "ping") {
        // Server keepalive
        return { type: "ping" }
      }

      if (eventName === "close") {
        // Stream close event
        return { type: "close" }
      }

      if (eventName === "open") {
        // Stream initialization - ignore
        return null
      }

      return null
    },

    _safeJson(s) {
      if (!s) return null
      try {
        return JSON.parse(s)
      } catch (_) {
        return null
      }
    },
  },

  // Add accessibility hooks
  ...AccessibilityHooks,

  // Admin Dashboard Micro-interactions
  AdminMicroInteractions: {
    mounted() {
      this.initializeAnimations();
      this.setupStaggerAnimations();
      this.setupTooltips();
      this.setupProgressBars();
      this.setupNotifications();
    },

    updated() {
      this.setupStaggerAnimations();
      this.updateProgressBars();
    },

    initializeAnimations() {
      // Add page transition classes
      if (this.el.classList.contains('admin-page')) {
        this.el.classList.add('page-transition-enter');
        requestAnimationFrame(() => {
          this.el.classList.add('page-transition-enter-active');
          this.el.classList.remove('page-transition-enter');
        });
      }

      // Setup card hover effects
      const cards = this.el.querySelectorAll('.card');
      cards.forEach(card => {
        card.addEventListener('mouseenter', () => {
          card.style.transform = 'translateY(-4px)';
        });
        card.addEventListener('mouseleave', () => {
          card.style.transform = 'translateY(0)';
        });
      });

      // Setup button interactions
      const buttons = this.el.querySelectorAll('.btn');
      buttons.forEach(button => {
        button.addEventListener('mousedown', () => {
          button.style.transform = 'scale(0.95)';
        });
        button.addEventListener('mouseup', () => {
          button.style.transform = 'scale(1.05)';
          setTimeout(() => {
            button.style.transform = 'scale(1)';
          }, 150);
        });
        button.addEventListener('mouseleave', () => {
          button.style.transform = 'scale(1)';
        });
      });
    },

    setupStaggerAnimations() {
      const staggerItems = this.el.querySelectorAll('.stagger-item:not(.animate)');
      staggerItems.forEach((item, index) => {
        setTimeout(() => {
          item.classList.add('animate');
        }, index * 100);
      });
    },

    setupTooltips() {
      const tooltipTriggers = this.el.querySelectorAll('[data-tooltip]');
      tooltipTriggers.forEach(trigger => {
        const tooltipText = trigger.getAttribute('data-tooltip');
        let tooltip = null;

        trigger.addEventListener('mouseenter', (e) => {
          tooltip = document.createElement('div');
          tooltip.className = 'tooltip show';
          tooltip.textContent = tooltipText;
          tooltip.setAttribute('role', 'tooltip');
          document.body.appendChild(tooltip);

          const rect = trigger.getBoundingClientRect();
          tooltip.style.position = 'absolute';
          tooltip.style.left = `${rect.left + rect.width / 2 - tooltip.offsetWidth / 2}px`;
          tooltip.style.top = `${rect.top - tooltip.offsetHeight - 8}px`;
          tooltip.style.zIndex = '9999';
        });

        trigger.addEventListener('mouseleave', () => {
          if (tooltip) {
            tooltip.classList.remove('show');
            setTimeout(() => {
              if (tooltip && tooltip.parentNode) {
                tooltip.parentNode.removeChild(tooltip);
              }
            }, 200);
          }
        });
      });
    },

    setupProgressBars() {
      const progressBars = this.el.querySelectorAll('[role="progressbar"]');
      progressBars.forEach(bar => {
        const value = bar.getAttribute('aria-valuenow');
        const max = bar.getAttribute('aria-valuemax') || 100;
        const percentage = (value / max) * 100;
        
        const fill = bar.querySelector('.progress-fill') || bar;
        fill.style.setProperty('--progress-value', `${percentage}%`);
        
        // Animate the progress bar
        setTimeout(() => {
          fill.style.width = `${percentage}%`;
        }, 100);
      });
    },

    updateProgressBars() {
      this.setupProgressBars();
    },

    setupNotifications() {
      const notifications = this.el.querySelectorAll('.notification:not(.notification-initialized)');
      notifications.forEach(notification => {
        notification.classList.add('notification-initialized');
        notification.classList.add('notification-enter');
        
        requestAnimationFrame(() => {
          notification.classList.add('notification-enter-active');
          notification.classList.remove('notification-enter');
        });

        // Auto-dismiss after 5 seconds
        setTimeout(() => {
          notification.classList.add('notification-exit');
          notification.classList.add('notification-exit-active');
          setTimeout(() => {
            if (notification.parentNode) {
              notification.parentNode.removeChild(notification);
            }
          }, 300);
        }, 5000);
      });
    }
  },

  // Enhanced Table Interactions
  AdminTableInteractions: {
    mounted() {
      this.setupTableAnimations();
      this.setupSortableHeaders();
    },

    updated() {
      this.setupTableAnimations();
    },

    setupTableAnimations() {
      const rows = this.el.querySelectorAll('tbody tr');
      rows.forEach((row, index) => {
        row.style.animationDelay = `${index * 50}ms`;
        row.classList.add('stagger-item');
        
        setTimeout(() => {
          row.classList.add('animate');
        }, index * 50);
      });
    },

    setupSortableHeaders() {
      const sortableHeaders = this.el.querySelectorAll('th[aria-sort]');
      sortableHeaders.forEach(header => {
        header.addEventListener('click', () => {
          // Add visual feedback for sorting
          header.style.transform = 'scale(0.95)';
          setTimeout(() => {
            header.style.transform = 'scale(1)';
          }, 150);
        });
      });
    }
  },

  // Modal Animations
  AdminModalAnimations: {
    mounted() {
      this.setupModalAnimations();
    },

    setupModalAnimations() {
      const modal = this.el;
      const backdrop = modal.querySelector('.modal-backdrop');
      const content = modal.querySelector('.modal-content');

      if (backdrop && content) {
        // Initial state
        backdrop.classList.add('entering');
        content.classList.add('entering');

        // Animate in
        requestAnimationFrame(() => {
          backdrop.classList.remove('entering');
          backdrop.classList.add('entered');
          content.classList.remove('entering');
          content.classList.add('entered');
        });
      }
    },

    beforeDestroy() {
      const modal = this.el;
      const backdrop = modal.querySelector('.modal-backdrop');
      const content = modal.querySelector('.modal-content');

      if (backdrop && content) {
        backdrop.classList.remove('entered');
        content.classList.remove('entered');
      }
    }
  },

  // Loading States
  AdminLoadingStates: {
    mounted() {
      this.setupLoadingStates();
    },

    updated() {
      this.setupLoadingStates();
    },

    setupLoadingStates() {
      // Show loading skeletons while data loads
      const loadingElements = this.el.querySelectorAll('[data-loading="true"]');
      loadingElements.forEach(element => {
        if (!element.querySelector('.skeleton')) {
          this.addLoadingSkeleton(element);
        }
      });

      // Remove loading skeletons when data is loaded
      const loadedElements = this.el.querySelectorAll('[data-loading="false"]');
      loadedElements.forEach(element => {
        this.removeLoadingSkeleton(element);
      });
    },

    addLoadingSkeleton(element) {
      const skeleton = document.createElement('div');
      skeleton.className = 'skeleton-card';
      skeleton.innerHTML = `
        <div class="skeleton-line long"></div>
        <div class="skeleton-line medium"></div>
        <div class="skeleton-line short"></div>
      `;
      element.appendChild(skeleton);
    },

    removeLoadingSkeleton(element) {
      const skeleton = element.querySelector('.skeleton, .skeleton-card');
      if (skeleton) {
        skeleton.style.opacity = '0';
        setTimeout(() => {
          if (skeleton.parentNode) {
            skeleton.parentNode.removeChild(skeleton);
          }
        }, 300);
      }
    }
  },

  // Search Enhancements
  AdminSearchEnhancements: {
    mounted() {
      this.setupSearchAnimations();
    },

    setupSearchAnimations() {
      const searchInputs = this.el.querySelectorAll('.search-input input');
      searchInputs.forEach(input => {
        const container = input.closest('.search-input');
        const icon = container?.querySelector('.search-icon');

        input.addEventListener('focus', () => {
          if (icon) {
            icon.style.transform = 'scale(1.1)';
            icon.style.color = 'oklch(var(--color-primary))';
          }
          container?.classList.add('focused');
        });

        input.addEventListener('blur', () => {
          if (icon) {
            icon.style.transform = 'scale(1)';
            icon.style.color = '';
          }
          container?.classList.remove('focused');
        });

        input.addEventListener('input', () => {
          if (input.value) {
            container?.classList.add('has-value');
          } else {
            container?.classList.remove('has-value');
          }
        });
      });
    }
  },

  // Status Indicators
  AdminStatusIndicators: {
    mounted() {
      this.updateStatusIndicators();
    },

    updated() {
      this.updateStatusIndicators();
    },

    updateStatusIndicators() {
      const indicators = this.el.querySelectorAll('.status-indicator');
      indicators.forEach(indicator => {
        const status = indicator.getAttribute('data-status');
        
        // Remove existing status classes
        indicator.classList.remove('online', 'offline', 'busy');
        
        // Add current status class
        if (status) {
          indicator.classList.add(status);
        }
      });
    }
  },

  // Admin Sidebar Persistence
  AdminSidebarPersistence: {
    mounted() {
      // Restore sidebar state from localStorage on mount
      const savedState = localStorage.getItem('admin-sidebar-collapsed');
      if (savedState !== null) {
        const isCollapsed = savedState === 'true';
        this.pushEvent('set_sidebar_state', { collapsed: isCollapsed });
      }
    },

    updated() {
      // Save sidebar state to localStorage when it changes
      const sidebarElement = document.getElementById('admin-sidebar');
      if (sidebarElement) {
        const isCollapsed = sidebarElement.classList.contains('-translate-x-full') || 
                           sidebarElement.classList.contains('lg:w-16');
        localStorage.setItem('admin-sidebar-collapsed', isCollapsed.toString());
      }
    }
  }
}

// ----------------------------------------------------------------------------
// LiveSocket setup
// ----------------------------------------------------------------------------

let csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")

let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", () => topbar.show(300))
window.addEventListener("phx:page-loading-stop", () => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// ----------------------------------------------------------------------------
// Admin Dashboard Utilities
// ----------------------------------------------------------------------------

// Global utilities for admin dashboard
window.AdminDashboard = {
  // Smooth scroll to element
  scrollTo(elementId) {
    const element = document.getElementById(elementId);
    if (element) {
      element.scrollIntoView({ 
        behavior: 'smooth', 
        block: 'start' 
      });
    }
  },

  // Toggle theme
  toggleTheme() {
    const html = document.documentElement;
    const currentTheme = html.getAttribute('data-theme');
    const newTheme = currentTheme === 'dark' ? 'light' : 'dark';
    html.setAttribute('data-theme', newTheme);
    localStorage.setItem('admin-theme', newTheme);
  },

  // Toggle high contrast
  toggleHighContrast() {
    document.body.classList.toggle('high-contrast');
    const isHighContrast = document.body.classList.contains('high-contrast');
    localStorage.setItem('admin-high-contrast', isHighContrast);
  },

  // Toggle reduced motion
  toggleReducedMotion() {
    document.body.classList.toggle('reduce-motion');
    const isReducedMotion = document.body.classList.contains('reduce-motion');
    localStorage.setItem('admin-reduced-motion', isReducedMotion);
  },

  // Show notification
  showNotification(message, type = 'info', duration = 5000) {
    const notification = document.createElement('div');
    notification.className = `notification alert alert-${type} fixed top-4 right-4 z-50 max-w-sm`;
    notification.innerHTML = `
      <div class="flex items-center gap-2">
        <span>${message}</span>
        <button class="btn btn-ghost btn-xs" onclick="this.parentElement.parentElement.remove()">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
          </svg>
        </button>
      </div>
    `;

    document.body.appendChild(notification);

    // Trigger animation
    requestAnimationFrame(() => {
      notification.classList.add('notification-enter-active');
    });

    // Auto remove
    setTimeout(() => {
      notification.classList.add('notification-exit-active');
      setTimeout(() => {
        if (notification.parentNode) {
          notification.parentNode.removeChild(notification);
        }
      }, 300);
    }, duration);
  },

  // Copy to clipboard with feedback
  async copyToClipboard(text, feedbackMessage = 'Copied to clipboard!') {
    try {
      await navigator.clipboard.writeText(text);
      this.showNotification(feedbackMessage, 'success', 2000);
    } catch (err) {
      console.error('Failed to copy text: ', err);
      this.showNotification('Failed to copy to clipboard', 'error', 3000);
    }
  },

  // Format numbers with animations
  animateNumber(element, targetValue, duration = 1000) {
    const startValue = parseInt(element.textContent) || 0;
    const increment = (targetValue - startValue) / (duration / 16);
    let currentValue = startValue;

    const timer = setInterval(() => {
      currentValue += increment;
      if ((increment > 0 && currentValue >= targetValue) || 
          (increment < 0 && currentValue <= targetValue)) {
        currentValue = targetValue;
        clearInterval(timer);
      }
      element.textContent = Math.round(currentValue).toLocaleString();
    }, 16);
  },

  // Initialize dashboard on page load
  init() {
    // Restore user preferences
    const savedTheme = localStorage.getItem('admin-theme');
    if (savedTheme) {
      document.documentElement.setAttribute('data-theme', savedTheme);
    }

    const savedHighContrast = localStorage.getItem('admin-high-contrast');
    if (savedHighContrast === 'true') {
      document.body.classList.add('high-contrast');
    }

    const savedReducedMotion = localStorage.getItem('admin-reduced-motion');
    if (savedReducedMotion === 'true') {
      document.body.classList.add('reduce-motion');
    }

    // Setup keyboard shortcuts
    document.addEventListener('keydown', (e) => {
      // Alt + T for theme toggle
      if (e.altKey && e.key === 't') {
        e.preventDefault();
        this.toggleTheme();
      }
      
      // Alt + C for high contrast toggle
      if (e.altKey && e.key === 'c') {
        e.preventDefault();
        this.toggleHighContrast();
      }
      
      // Alt + M for reduced motion toggle
      if (e.altKey && e.key === 'm') {
        e.preventDefault();
        this.toggleReducedMotion();
      }
    });

    // Setup intersection observer for animations
    const observerOptions = {
      threshold: 0.1,
      rootMargin: '0px 0px -50px 0px'
    };

    const observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.classList.add('animate');
          
          // Animate numbers if they have data-animate-number
          const numberElements = entry.target.querySelectorAll('[data-animate-number]');
          numberElements.forEach(el => {
            const targetValue = parseInt(el.getAttribute('data-animate-number'));
            this.animateNumber(el, targetValue);
          });
        }
      });
    }, observerOptions);

    // Observe elements that should animate on scroll
    document.querySelectorAll('.stagger-item, [data-animate-number]').forEach(el => {
      observer.observe(el);
    });
  }
};

// Initialize admin dashboard utilities when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
  window.AdminDashboard.init();
});

// Handle page visibility changes for performance
document.addEventListener('visibilitychange', () => {
  if (document.hidden) {
    // Pause animations when page is not visible
    document.body.classList.add('paused-animations');
  } else {
    // Resume animations when page becomes visible
    document.body.classList.remove('paused-animations');
  }
});

// expose liveSocket on window for web console debug logs and latency simulation:
window.liveSocket = liveSocket