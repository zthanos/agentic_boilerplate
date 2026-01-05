// Admin Profiles LiveView Hooks for Enhanced UX

// Auto-dismiss flash messages
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

// Form keyboard shortcuts
const FormKeyboardShortcuts = {
  mounted() {
    this.handleKeydown = (e) => {
      // Save shortcut (Ctrl+S or Cmd+S)
      if ((e.ctrlKey || e.metaKey) && e.key === 's') {
        e.preventDefault();
        const submitButton = this.el.querySelector('button[type="submit"]');
        if (submitButton && !submitButton.disabled) {
          submitButton.click();
        }
      }
      
      // Cancel shortcut (Escape)
      if (e.key === 'Escape') {
        e.preventDefault();
        const cancelButton = this.el.querySelector('button[phx-click="back_to_list"]');
        if (cancelButton && !cancelButton.disabled) {
          cancelButton.click();
        }
      }
    };
    
    document.addEventListener('keydown', this.handleKeydown);
  },
  
  destroyed() {
    document.removeEventListener('keydown', this.handleKeydown);
  }
};

// Export hooks
export { AutoDismissFlash, FormKeyboardShortcuts };