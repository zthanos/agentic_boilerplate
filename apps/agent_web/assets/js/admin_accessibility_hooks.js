/**
 * Admin Dashboard Accessibility Hooks
 * 
 * Provides JavaScript functionality for enhanced accessibility features:
 * - Focus management and trapping
 * - Keyboard navigation
 * - Screen reader announcements
 * - High contrast and reduced motion support
 */

// Focus Trap Hook for Modal Dialogs
export const FocusTrap = {
  mounted() {
    this.focusableElements = this.getFocusableElements();
    this.firstFocusable = this.focusableElements[0];
    this.lastFocusable = this.focusableElements[this.focusableElements.length - 1];
    
    // Focus the first element when mounted
    if (this.firstFocusable) {
      this.firstFocusable.focus();
    }
    
    // Add event listeners
    this.handleKeyDown = this.handleKeyDown.bind(this);
    this.el.addEventListener('keydown', this.handleKeyDown);
    
    // Store the previously focused element to restore later
    this.previouslyFocused = document.activeElement;
  },
  
  destroyed() {
    this.el.removeEventListener('keydown', this.handleKeyDown);
    
    // Restore focus to previously focused element
    if (this.previouslyFocused && this.previouslyFocused.focus) {
      this.previouslyFocused.focus();
    }
  },
  
  handleKeyDown(event) {
    if (event.key === 'Tab') {
      if (event.shiftKey) {
        // Shift + Tab - move backwards
        if (document.activeElement === this.firstFocusable) {
          event.preventDefault();
          this.lastFocusable.focus();
        }
      } else {
        // Tab - move forwards
        if (document.activeElement === this.lastFocusable) {
          event.preventDefault();
          this.firstFocusable.focus();
        }
      }
    } else if (event.key === 'Escape') {
      // Close modal on Escape
      this.pushEvent('close_modal');
    }
  },
  
  getFocusableElements() {
    const focusableSelectors = [
      'button:not([disabled])',
      'input:not([disabled])',
      'select:not([disabled])',
      'textarea:not([disabled])',
      'a[href]',
      '[tabindex]:not([tabindex="-1"])'
    ].join(', ');
    
    return Array.from(this.el.querySelectorAll(focusableSelectors));
  }
};

// Keyboard Navigation Hook for Menus and Lists
export const KeyboardNav = {
  mounted() {
    this.navType = this.el.dataset.navType || 'menu';
    this.items = this.getNavigableItems();
    this.currentIndex = 0;
    
    this.handleKeyDown = this.handleKeyDown.bind(this);
    this.el.addEventListener('keydown', this.handleKeyDown);
    
    // Set initial focus
    this.updateFocus();
  },
  
  destroyed() {
    this.el.removeEventListener('keydown', this.handleKeyDown);
  },
  
  updated() {
    // Refresh items when the DOM updates
    this.items = this.getNavigableItems();
    this.updateFocus();
  },
  
  handleKeyDown(event) {
    switch (this.navType) {
      case 'menu':
        this.handleMenuNavigation(event);
        break;
      case 'tabs':
        this.handleTabNavigation(event);
        break;
      case 'table':
        this.handleTableNavigation(event);
        break;
    }
  },
  
  handleMenuNavigation(event) {
    switch (event.key) {
      case 'ArrowDown':
        event.preventDefault();
        this.moveNext();
        break;
      case 'ArrowUp':
        event.preventDefault();
        this.movePrevious();
        break;
      case 'Home':
        event.preventDefault();
        this.moveToFirst();
        break;
      case 'End':
        event.preventDefault();
        this.moveToLast();
        break;
      case 'Enter':
      case ' ':
        event.preventDefault();
        this.activateCurrentItem();
        break;
      case 'Escape':
        this.pushEvent('close_menu');
        break;
    }
  },
  
  handleTabNavigation(event) {
    switch (event.key) {
      case 'ArrowLeft':
        event.preventDefault();
        this.movePrevious();
        break;
      case 'ArrowRight':
        event.preventDefault();
        this.moveNext();
        break;
      case 'Home':
        event.preventDefault();
        this.moveToFirst();
        break;
      case 'End':
        event.preventDefault();
        this.moveToLast();
        break;
    }
  },
  
  handleTableNavigation(event) {
    // Table navigation would be more complex, implementing basic version
    switch (event.key) {
      case 'ArrowDown':
        event.preventDefault();
        this.moveNext();
        break;
      case 'ArrowUp':
        event.preventDefault();
        this.movePrevious();
        break;
    }
  },
  
  moveNext() {
    this.currentIndex = (this.currentIndex + 1) % this.items.length;
    this.updateFocus();
  },
  
  movePrevious() {
    this.currentIndex = this.currentIndex === 0 ? this.items.length - 1 : this.currentIndex - 1;
    this.updateFocus();
  },
  
  moveToFirst() {
    this.currentIndex = 0;
    this.updateFocus();
  },
  
  moveToLast() {
    this.currentIndex = this.items.length - 1;
    this.updateFocus();
  },
  
  updateFocus() {
    // Remove tabindex from all items
    this.items.forEach(item => item.setAttribute('tabindex', '-1'));
    
    // Set current item as focusable and focus it
    if (this.items[this.currentIndex]) {
      this.items[this.currentIndex].setAttribute('tabindex', '0');
      this.items[this.currentIndex].focus();
    }
  },
  
  activateCurrentItem() {
    if (this.items[this.currentIndex]) {
      this.items[this.currentIndex].click();
    }
  },
  
  getNavigableItems() {
    const selector = this.navType === 'tabs' ? '[role="tab"]' : '[role="menuitem"], a, button';
    return Array.from(this.el.querySelectorAll(selector));
  }
};

// Screen Reader Announcements Hook
export const ScreenReaderAnnouncer = {
  mounted() {
    this.createAnnouncementRegion();
  },
  
  destroyed() {
    if (this.announcementRegion) {
      this.announcementRegion.remove();
    }
  },
  
  createAnnouncementRegion() {
    // Create a live region for screen reader announcements
    this.announcementRegion = document.createElement('div');
    this.announcementRegion.setAttribute('aria-live', 'polite');
    this.announcementRegion.setAttribute('aria-atomic', 'true');
    this.announcementRegion.className = 'sr-only';
    this.announcementRegion.id = 'screen-reader-announcements';
    
    document.body.appendChild(this.announcementRegion);
    
    // Listen for announcement events
    this.handleEvent('announce', ({ message, priority = 'polite' }) => {
      this.announce(message, priority);
    });
  },
  
  announce(message, priority = 'polite') {
    if (!this.announcementRegion) return;
    
    // Set the priority level
    this.announcementRegion.setAttribute('aria-live', priority);
    
    // Clear and set the message
    this.announcementRegion.textContent = '';
    
    // Use setTimeout to ensure screen readers pick up the change
    setTimeout(() => {
      this.announcementRegion.textContent = message;
    }, 100);
    
    // Clear the message after a delay to allow for re-announcements
    setTimeout(() => {
      this.announcementRegion.textContent = '';
    }, 1000);
  }
};

// Skip Links Hook
export const SkipLinks = {
  mounted() {
    this.createSkipLinks();
  },
  
  createSkipLinks() {
    const skipLinksContainer = document.createElement('div');
    skipLinksContainer.className = 'skip-links';
    skipLinksContainer.innerHTML = `
      <a href="#main-content" class="skip-link">Skip to main content</a>
      <a href="#admin-sidebar" class="skip-link">Skip to navigation</a>
      <a href="#admin-footer" class="skip-link">Skip to footer</a>
    `;
    
    // Insert at the beginning of the body
    document.body.insertBefore(skipLinksContainer, document.body.firstChild);
  }
};

// High Contrast Mode Hook
export const HighContrastMode = {
  mounted() {
    this.checkHighContrastPreference();
    this.addHighContrastToggle();
  },
  
  checkHighContrastPreference() {
    // Check for system preference
    if (window.matchMedia('(prefers-contrast: high)').matches) {
      document.documentElement.classList.add('high-contrast');
    }
    
    // Check for stored preference
    const storedPreference = localStorage.getItem('high-contrast-mode');
    if (storedPreference === 'enabled') {
      document.documentElement.classList.add('high-contrast');
    }
  },
  
  addHighContrastToggle() {
    // This would typically be added to the admin navbar
    this.handleEvent('toggle_high_contrast', () => {
      this.toggleHighContrast();
    });
  },
  
  toggleHighContrast() {
    const isEnabled = document.documentElement.classList.toggle('high-contrast');
    localStorage.setItem('high-contrast-mode', isEnabled ? 'enabled' : 'disabled');
    
    // Announce the change
    const message = isEnabled ? 'High contrast mode enabled' : 'High contrast mode disabled';
    this.pushEvent('announce', { message });
  }
};

// Reduced Motion Hook
export const ReducedMotion = {
  mounted() {
    this.checkMotionPreference();
  },
  
  checkMotionPreference() {
    // Check for system preference
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      document.documentElement.classList.add('reduce-motion');
    }
    
    // Check for stored preference
    const storedPreference = localStorage.getItem('reduced-motion');
    if (storedPreference === 'enabled') {
      document.documentElement.classList.add('reduce-motion');
    }
  },
  
  toggleReducedMotion() {
    const isEnabled = document.documentElement.classList.toggle('reduce-motion');
    localStorage.setItem('reduced-motion', isEnabled ? 'enabled' : 'disabled');
    
    // Announce the change
    const message = isEnabled ? 'Reduced motion enabled' : 'Reduced motion disabled';
    this.pushEvent('announce', { message });
  }
};

// Form Accessibility Hook
export const FormAccessibility = {
  mounted() {
    this.enhanceFormAccessibility();
  },
  
  enhanceFormAccessibility() {
    // Add live validation feedback
    const inputs = this.el.querySelectorAll('input, select, textarea');
    inputs.forEach(input => {
      input.addEventListener('blur', this.validateField.bind(this));
      input.addEventListener('invalid', this.handleInvalidField.bind(this));
    });
  },
  
  validateField(event) {
    const field = event.target;
    const errorElement = document.getElementById(`${field.name}-error`);
    
    if (field.validity.valid) {
      field.setAttribute('aria-invalid', 'false');
      if (errorElement) {
        errorElement.textContent = '';
      }
    } else {
      field.setAttribute('aria-invalid', 'true');
      if (errorElement) {
        errorElement.textContent = field.validationMessage;
      }
    }
  },
  
  handleInvalidField(event) {
    const field = event.target;
    
    // Announce validation error to screen readers
    this.pushEvent('announce', {
      message: `${field.getAttribute('aria-label') || field.name}: ${field.validationMessage}`,
      priority: 'assertive'
    });
  }
};

// Export all hooks
export default {
  FocusTrap,
  KeyboardNav,
  ScreenReaderAnnouncer,
  SkipLinks,
  HighContrastMode,
  ReducedMotion,
  FormAccessibility
};