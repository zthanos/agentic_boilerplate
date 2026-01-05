// Admin Providers LiveView Hooks for Enhanced UX and Error Handling

// Enhanced auto-dismiss flash messages with progress bars
const AutoDismissFlash = {
  mounted() {
    const delay = parseInt(this.el.dataset.dismissDelay) || 5000;
    
    // Auto-dismiss after delay
    this.timeout = setTimeout(() => {
      this.el.style.display = 'none';
    }, delay);
    
    // Clear timeout if user manually dismisses
    this.el.addEventListener('click', (e) => {
      if (e.target.closest('button')) {
        clearTimeout(this.timeout);
      }
    });
  },
  
  destroyed() {
    if (this.timeout) {
      clearTimeout(this.timeout);
    }
  }
};

// Real-time form validation with debouncing
const RealTimeValidation = {
  mounted() {
    this.debounceTimeout = null;
    this.validationDelay = 500; // 500ms debounce
    
    // Find all form inputs
    const inputs = this.el.querySelectorAll('input, select, textarea');
    
    inputs.forEach(input => {
      // Add real-time validation on input change
      input.addEventListener('input', (e) => {
        this.debounceValidation(e.target);
      });
      
      // Add validation on blur for immediate feedback
      input.addEventListener('blur', (e) => {
        this.validateField(e.target);
      });
      
      // Enhanced visual feedback
      input.addEventListener('focus', (e) => {
        this.clearFieldError(e.target);
      });
    });
  },
  
  debounceValidation(field) {
    clearTimeout(this.debounceTimeout);
    this.debounceTimeout = setTimeout(() => {
      this.validateField(field);
    }, this.validationDelay);
  },
  
  validateField(field) {
    // Get form data
    const formData = new FormData(this.el);
    const params = {};
    
    // Convert FormData to object
    for (let [key, value] of formData.entries()) {
      params[key] = value;
    }
    
    // Trigger validation event
    this.pushEvent('validate_provider', { provider: params });
  },
  
  clearFieldError(field) {
    // Remove error styling
    field.classList.remove('input-error', 'border-error');
    
    // Hide error message
    const errorElement = field.parentElement.querySelector('.text-error');
    if (errorElement) {
      errorElement.style.display = 'none';
    }
  },
  
  destroyed() {
    if (this.debounceTimeout) {
      clearTimeout(this.debounceTimeout);
    }
  }
};

// Enhanced loading states with progress indicators
const LoadingStateManager = {
  mounted() {
    this.originalContent = new Map();
    
    // Monitor buttons for loading states
    this.observeButtons();
  },
  
  observeButtons() {
    const buttons = this.el.querySelectorAll('button[phx-click]');
    
    buttons.forEach(button => {
      // Store original content
      this.originalContent.set(button, {
        innerHTML: button.innerHTML,
        disabled: button.disabled
      });
      
      // Add click handler for immediate feedback
      button.addEventListener('click', (e) => {
        this.setButtonLoading(button, e.target.getAttribute('phx-click'));
      });
    });
  },
  
  setButtonLoading(button, action) {
    // Don't modify if already loading
    if (button.classList.contains('loading')) return;
    
    // Add loading state
    button.classList.add('loading');
    button.disabled = true;
    
    // Add loading text based on action
    const loadingText = this.getLoadingText(action);
    if (loadingText) {
      const textElement = button.querySelector('.loading-text') || 
        document.createElement('span');
      textElement.className = 'loading-text ml-2';
      textElement.textContent = loadingText;
      
      if (!button.querySelector('.loading-text')) {
        button.appendChild(textElement);
      }
    }
    
    // Auto-restore after timeout (fallback)
    setTimeout(() => {
      this.restoreButton(button);
    }, 30000); // 30 second timeout
  },
  
  restoreButton(button) {
    const original = this.originalContent.get(button);
    if (original) {
      button.innerHTML = original.innerHTML;
      button.disabled = original.disabled;
      button.classList.remove('loading');
    }
  },
  
  getLoadingText(action) {
    const loadingTexts = {
      'test_connection': 'Testing...',
      'test_authentication': 'Authenticating...',
      'perform_health_check': 'Checking...',
      'save_provider': 'Saving...',
      'delete_provider': 'Deleting...',
      'test_all_connections': 'Testing All...',
      'perform_bulk_health_check': 'Checking All...'
    };
    
    return loadingTexts[action] || 'Processing...';
  }
};

// Connection test result display with animations
const ConnectionTestDisplay = {
  mounted() {
    this.animateResults();
  },
  
  updated() {
    this.animateResults();
  },
  
  animateResults() {
    // Animate test result cards
    const resultCards = this.el.querySelectorAll('.test-result-card');
    
    resultCards.forEach((card, index) => {
      card.style.opacity = '0';
      card.style.transform = 'translateY(20px)';
      
      setTimeout(() => {
        card.style.transition = 'all 0.3s ease-out';
        card.style.opacity = '1';
        card.style.transform = 'translateY(0)';
      }, index * 100);
    });
    
    // Animate progress bars
    const progressBars = this.el.querySelectorAll('.progress-bar');
    progressBars.forEach(bar => {
      const width = bar.dataset.width || '0%';
      bar.style.width = '0%';
      
      setTimeout(() => {
        bar.style.transition = 'width 1s ease-out';
        bar.style.width = width;
      }, 500);
    });
  }
};

// Comprehensive form keyboard shortcuts with enhanced feedback and accessibility
const FormKeyboardShortcuts = {
  mounted() {
    this.setupKeyboardShortcuts();
    this.setupAccessibilityFeatures();
    this.setupNavigationShortcuts();
    this.showKeyboardHints();
  },

  setupKeyboardShortcuts() {
    this.handleKeydown = (e) => {
      // Save shortcut (Ctrl+S or Cmd+S)
      if ((e.ctrlKey || e.metaKey) && e.key === 's') {
        e.preventDefault();
        const submitButton = this.el.querySelector('button[type="submit"], button[phx-click*="save"]');
        if (submitButton && !submitButton.disabled) {
          this.flashKeyboardHint('Saving provider...', 'success');
          submitButton.click();
        } else {
          this.flashKeyboardHint('Cannot save - form has errors or is loading', 'error');
        }
      }
      
      // Cancel shortcut (Escape)
      if (e.key === 'Escape') {
        e.preventDefault();
        const cancelButton = this.el.querySelector('button[phx-click="back_to_list"]');
        if (cancelButton && !cancelButton.disabled) {
          this.flashKeyboardHint('Returning to provider list', 'info');
          cancelButton.click();
        }
      }
      
      // Test connection shortcut (Ctrl+T or Cmd+T)
      if ((e.ctrlKey || e.metaKey) && e.key === 't') {
        e.preventDefault();
        const testButton = this.el.querySelector('button[phx-click="test_connection"]');
        if (testButton && !testButton.disabled) {
          this.flashKeyboardHint('Testing provider connection...', 'info');
          testButton.click();
        } else {
          this.flashKeyboardHint('Connection test not available', 'warning');
        }
      }

      // Test authentication shortcut (Ctrl+Shift+T or Cmd+Shift+T)
      if ((e.ctrlKey || e.metaKey) && e.shiftKey && e.key === 'T') {
        e.preventDefault();
        const authTestButton = this.el.querySelector('button[phx-click="test_authentication"]');
        if (authTestButton && !authTestButton.disabled) {
          this.flashKeyboardHint('Testing authentication...', 'info');
          authTestButton.click();
        } else {
          this.flashKeyboardHint('Authentication test not available', 'warning');
        }
      }

      // Quick navigation shortcuts
      if (e.altKey) {
        switch(e.key) {
          case '1':
            e.preventDefault();
            this.focusSection('basic-info');
            break;
          case '2':
            e.preventDefault();
            this.focusSection('connection-config');
            break;
          case '3':
            e.preventDefault();
            this.focusSection('authentication');
            break;
          case '4':
            e.preventDefault();
            this.focusSection('rate-limits');
            break;
          case '5':
            e.preventDefault();
            this.focusSection('cost-config');
            break;
        }
      }

      // Help shortcut (F1 or Ctrl+?)
      if (e.key === 'F1' || ((e.ctrlKey || e.metaKey) && e.key === '?')) {
        e.preventDefault();
        this.showHelpModal();
      }
    };
    
    document.addEventListener('keydown', this.handleKeydown);
  },

  setupAccessibilityFeatures() {
    // Add ARIA labels and descriptions
    const form = this.el.querySelector('form');
    if (form) {
      form.setAttribute('aria-label', 'Provider configuration form');
      form.setAttribute('role', 'form');
    }

    // Add skip links for keyboard navigation
    this.addSkipLinks();

    // Enhance form field accessibility
    this.enhanceFormAccessibility();

    // Add live region for status updates
    this.addLiveRegion();
  },

  setupNavigationShortcuts() {
    // Tab navigation enhancement
    const focusableElements = this.el.querySelectorAll(
      'input, select, textarea, button, [tabindex]:not([tabindex="-1"])'
    );

    focusableElements.forEach((element, index) => {
      element.addEventListener('keydown', (e) => {
        // Ctrl+Arrow keys for quick navigation between sections
        if (e.ctrlKey) {
          if (e.key === 'ArrowDown') {
            e.preventDefault();
            const nextSection = this.getNextSection(element);
            if (nextSection) {
              const firstInput = nextSection.querySelector('input, select, textarea');
              if (firstInput) firstInput.focus();
            }
          } else if (e.key === 'ArrowUp') {
            e.preventDefault();
            const prevSection = this.getPreviousSection(element);
            if (prevSection) {
              const firstInput = prevSection.querySelector('input, select, textarea');
              if (firstInput) firstInput.focus();
            }
          }
        }
      });
    });
  },

  addSkipLinks() {
    const skipLinksContainer = document.createElement('div');
    skipLinksContainer.className = 'skip-links';
    skipLinksContainer.innerHTML = `
      <a href="#basic-info" class="skip-link">Skip to Basic Information</a>
      <a href="#connection-config" class="skip-link">Skip to Connection Configuration</a>
      <a href="#authentication" class="skip-link">Skip to Authentication</a>
      <a href="#form-actions" class="skip-link">Skip to Form Actions</a>
    `;
    
    this.el.insertBefore(skipLinksContainer, this.el.firstChild);
  },

  enhanceFormAccessibility() {
    // Add required field indicators
    const requiredFields = this.el.querySelectorAll('input[required], select[required]');
    requiredFields.forEach(field => {
      const label = field.closest('.form-control')?.querySelector('label');
      if (label && !label.querySelector('.required-indicator')) {
        const indicator = document.createElement('span');
        indicator.className = 'required-indicator sr-only';
        indicator.textContent = ' (required)';
        label.appendChild(indicator);
      }
    });

    // Add error announcements
    const errorElements = this.el.querySelectorAll('.validation-error');
    errorElements.forEach(error => {
      error.setAttribute('role', 'alert');
      error.setAttribute('aria-live', 'polite');
    });
  },

  addLiveRegion() {
    if (!document.getElementById('provider-form-status')) {
      const liveRegion = document.createElement('div');
      liveRegion.id = 'provider-form-status';
      liveRegion.className = 'sr-only';
      liveRegion.setAttribute('aria-live', 'polite');
      liveRegion.setAttribute('aria-atomic', 'true');
      document.body.appendChild(liveRegion);
    }
  },

  announceStatus(message) {
    const liveRegion = document.getElementById('provider-form-status');
    if (liveRegion) {
      liveRegion.textContent = message;
    }
  },

  focusSection(sectionId) {
    const section = document.getElementById(sectionId);
    if (section) {
      const firstInput = section.querySelector('input, select, textarea');
      if (firstInput) {
        firstInput.focus();
        this.flashKeyboardHint(`Focused on ${section.querySelector('h4')?.textContent || sectionId}`, 'info');
      }
    }
  },

  getNextSection(element) {
    const currentSection = element.closest('.card');
    return currentSection?.nextElementSibling?.classList.contains('card') ? 
           currentSection.nextElementSibling : null;
  },

  getPreviousSection(element) {
    const currentSection = element.closest('.card');
    return currentSection?.previousElementSibling?.classList.contains('card') ? 
           currentSection.previousElementSibling : null;
  },

  showHelpModal() {
    const helpModal = document.createElement('div');
    helpModal.className = 'modal modal-open';
    helpModal.innerHTML = `
      <div class="modal-box max-w-4xl">
        <h3 class="font-bold text-lg mb-4">Provider Form Help & Keyboard Shortcuts</h3>
        
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div>
            <h4 class="font-semibold mb-2">Keyboard Shortcuts</h4>
            <ul class="space-y-2 text-sm">
              <li><kbd class="kbd kbd-sm">Ctrl+S</kbd> Save provider</li>
              <li><kbd class="kbd kbd-sm">Esc</kbd> Cancel and return to list</li>
              <li><kbd class="kbd kbd-sm">Ctrl+T</kbd> Test connection</li>
              <li><kbd class="kbd kbd-sm">Ctrl+Shift+T</kbd> Test authentication</li>
              <li><kbd class="kbd kbd-sm">Alt+1-5</kbd> Jump to form sections</li>
              <li><kbd class="kbd kbd-sm">F1</kbd> Show this help</li>
              <li><kbd class="kbd kbd-sm">Ctrl+↑/↓</kbd> Navigate between sections</li>
            </ul>
          </div>
          
          <div>
            <h4 class="font-semibold mb-2">Form Sections</h4>
            <ul class="space-y-2 text-sm">
              <li><kbd class="kbd kbd-sm">Alt+1</kbd> Basic Information</li>
              <li><kbd class="kbd kbd-sm">Alt+2</kbd> Connection Configuration</li>
              <li><kbd class="kbd kbd-sm">Alt+3</kbd> Authentication</li>
              <li><kbd class="kbd kbd-sm">Alt+4</kbd> Rate Limits</li>
              <li><kbd class="kbd kbd-sm">Alt+5</kbd> Cost Configuration</li>
            </ul>
          </div>
        </div>
        
        <div class="mt-6">
          <h4 class="font-semibold mb-2">Provider Types Guide</h4>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
            <div>
              <strong>Cloud:</strong> External services like OpenAI, Anthropic
              <br><em>Required: Base URL, Authentication</em>
            </div>
            <div>
              <strong>Local:</strong> Self-hosted services like Ollama
              <br><em>Required: Base URL (localhost/private IP)</em>
            </div>
            <div>
              <strong>Enterprise:</strong> Corporate AI services
              <br><em>Required: Base URL, Secure Authentication</em>
            </div>
            <div>
              <strong>Custom:</strong> Specialized or custom implementations
              <br><em>Required: Base URL</em>
            </div>
          </div>
        </div>
        
        <div class="modal-action">
          <button class="btn btn-primary" onclick="this.closest('.modal').remove()">
            Got it!
          </button>
        </div>
      </div>
      <div class="modal-backdrop" onclick="this.closest('.modal').remove()"></div>
    `;
    
    document.body.appendChild(helpModal);
    
    // Focus the close button for accessibility
    const closeButton = helpModal.querySelector('.btn');
    if (closeButton) closeButton.focus();
    
    // Close on Escape
    const closeOnEscape = (e) => {
      if (e.key === 'Escape') {
        helpModal.remove();
        document.removeEventListener('keydown', closeOnEscape);
      }
    };
    document.addEventListener('keydown', closeOnEscape);
  },
  
  flashKeyboardHint(message, type) {
    // Create temporary hint element
    const hint = document.createElement('div');
    hint.className = `alert alert-${type} fixed top-4 right-4 z-50 w-auto shadow-lg animate-in slide-in-from-right-2`;
    hint.setAttribute('role', 'status');
    hint.setAttribute('aria-live', 'polite');
    hint.innerHTML = `
      <div class="flex items-center gap-2">
        <span class="text-sm">${message}</span>
      </div>
    `;
    
    document.body.appendChild(hint);
    
    // Announce to screen readers
    this.announceStatus(message);
    
    // Remove after 2 seconds
    setTimeout(() => {
      hint.style.animation = 'slide-out-to-right-2 0.3s ease-in forwards';
      setTimeout(() => hint.remove(), 300);
    }, 2000);
  },
  
  showKeyboardHints() {
    // Add keyboard hints to relevant buttons
    const shortcuts = [
      { selector: 'button[type="submit"], button[phx-click*="save"]', hint: 'Ctrl+S', label: 'Save provider' },
      { selector: 'button[phx-click="back_to_list"]', hint: 'Esc', label: 'Cancel and return to list' },
      { selector: 'button[phx-click="test_connection"]', hint: 'Ctrl+T', label: 'Test connection' },
      { selector: 'button[phx-click="test_authentication"]', hint: 'Ctrl+Shift+T', label: 'Test authentication' }
    ];
    
    shortcuts.forEach(({ selector, hint, label }) => {
      const button = this.el.querySelector(selector);
      if (button && !button.querySelector('.keyboard-hint')) {
        // Add visual hint
        const hintElement = document.createElement('span');
        hintElement.className = 'keyboard-hint text-xs opacity-60 ml-1';
        hintElement.textContent = `(${hint})`;
        button.appendChild(hintElement);
        
        // Add accessibility attributes
        button.setAttribute('title', `${label} - Keyboard shortcut: ${hint}`);
        button.setAttribute('aria-keyshortcuts', hint.replace('Ctrl+', 'Control+').replace('Cmd+', 'Meta+'));
      }
    });

    // Add section navigation hints
    const sections = this.el.querySelectorAll('.card h4');
    sections.forEach((heading, index) => {
      const shortcut = `Alt+${index + 1}`;
      if (index < 5) { // Only for first 5 sections
        const hintElement = document.createElement('span');
        hintElement.className = 'keyboard-hint text-xs opacity-60 ml-2';
        hintElement.textContent = `(${shortcut})`;
        heading.appendChild(hintElement);
        
        // Add ID for navigation
        const section = heading.closest('.card');
        if (section && !section.id) {
          const sectionIds = ['basic-info', 'connection-config', 'authentication', 'rate-limits', 'cost-config'];
          section.id = sectionIds[index] || `section-${index + 1}`;
        }
      }
    });
  },
  
  destroyed() {
    document.removeEventListener('keydown', this.handleKeydown);
    
    // Clean up live region
    const liveRegion = document.getElementById('provider-form-status');
    if (liveRegion) {
      liveRegion.remove();
    }
  }
};

// Enhanced error display with copy functionality and accessibility
const ErrorDisplay = {
  mounted() {
    this.addCopyButtons();
    this.enhanceAccessibility();
  },
  
  updated() {
    this.addCopyButtons();
    this.enhanceAccessibility();
  },
  
  addCopyButtons() {
    const errorElements = this.el.querySelectorAll('.error-message, .validation-error');
    
    errorElements.forEach(element => {
      if (!element.querySelector('.copy-error-btn')) {
        const copyBtn = document.createElement('button');
        copyBtn.className = 'copy-error-btn btn btn-ghost btn-xs ml-2';
        copyBtn.innerHTML = '<svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20"><path d="M8 3a1 1 0 011-1h2a1 1 0 110 2H9a1 1 0 01-1-1z"></path><path d="M6 3a2 2 0 00-2 2v11a2 2 0 002 2h8a2 2 0 002-2V5a2 2 0 00-2-2 3 3 0 01-3 3H9a3 3 0 01-3-3z"></path></svg>';
        copyBtn.title = 'Copy error message to clipboard';
        copyBtn.setAttribute('aria-label', 'Copy error message to clipboard');
        
        copyBtn.addEventListener('click', async () => {
          try {
            await navigator.clipboard.writeText(element.textContent);
            this.showCopyFeedback(copyBtn);
            this.announceToScreenReader('Error message copied to clipboard');
          } catch (err) {
            console.error('Failed to copy text: ', err);
            this.announceToScreenReader('Failed to copy error message');
          }
        });
        
        element.appendChild(copyBtn);
      }
    });
  },

  enhanceAccessibility() {
    const errorElements = this.el.querySelectorAll('.error-message, .validation-error');
    
    errorElements.forEach(element => {
      // Add ARIA attributes for screen readers
      element.setAttribute('role', 'alert');
      element.setAttribute('aria-live', 'assertive');
      
      // Add error icon with proper labeling
      if (!element.querySelector('.error-icon')) {
        const icon = document.createElement('span');
        icon.className = 'error-icon mr-2';
        icon.setAttribute('aria-hidden', 'true');
        icon.innerHTML = '⚠️';
        element.insertBefore(icon, element.firstChild);
      }
    });
  },

  announceToScreenReader(message) {
    // Create temporary element for screen reader announcement
    const announcement = document.createElement('div');
    announcement.className = 'sr-only';
    announcement.setAttribute('aria-live', 'polite');
    announcement.textContent = message;
    
    document.body.appendChild(announcement);
    
    // Remove after announcement
    setTimeout(() => {
      announcement.remove();
    }, 1000);
  },
  
  showCopyFeedback(button) {
    const original = button.innerHTML;
    button.innerHTML = '<svg class="w-3 h-3 text-success" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"></path></svg>';
    button.title = 'Copied!';
    
    setTimeout(() => {
      button.innerHTML = original;
      button.title = 'Copy error message to clipboard';
    }, 1500);
  }
};

// Global help handler for F1 key
const GlobalHelpHandler = {
  mounted() {
    this.handleGlobalKeydown = (e) => {
      // F1 key for global help
      if (e.key === 'F1') {
        e.preventDefault();
        // Trigger the LiveView's toggle_help event
        this.pushEvent('toggle_help', {});
      }
    };
    
    document.addEventListener('keydown', this.handleGlobalKeydown);
  },
  
  destroyed() {
    if (this.handleGlobalKeydown) {
      document.removeEventListener('keydown', this.handleGlobalKeydown);
    }
  }
};

// Export hooks
export { 
  AutoDismissFlash, 
  RealTimeValidation, 
  LoadingStateManager, 
  ConnectionTestDisplay, 
  FormKeyboardShortcuts, 
  ErrorDisplay,
  GlobalHelpHandler
};