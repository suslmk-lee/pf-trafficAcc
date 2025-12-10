/**
 * Health Check and Auto-Reload for GSLB Failover
 *
 * Monitors frontend connectivity and automatically reloads the page
 * when the current cluster becomes unavailable, allowing GSLB to
 * redirect to the healthy cluster.
 */

class HealthMonitor {
  constructor(options = {}) {
    this.checkInterval = options.checkInterval || 5000; // 5 seconds
    this.failureThreshold = options.failureThreshold || 2; // 2 consecutive failures
    this.consecutiveFailures = 0;
    this.intervalId = null;
    this.isChecking = false;
    this.isTransitioning = false; // Track cluster transition state
  }

  async checkHealth() {
    if (this.isChecking) return;

    this.isChecking = true;

    try {
      // Check if we can reach the frontend itself
      const response = await fetch('/health', {
        method: 'GET',
        cache: 'no-cache',
        signal: AbortSignal.timeout(3000) // 3 second timeout
      });

      if (response.ok) {
        // Health check passed
        this.consecutiveFailures = 0;

        // If we were transitioning, clear the flag and hide notification
        if (this.isTransitioning) {
          console.log('[HealthCheck] ✓ Cluster transition completed - service restored');
          this.isTransitioning = false;
          this.hideReloadNotification();
        } else {
          console.log('[HealthCheck] ✓ Cluster healthy');
        }
      } else {
        this.handleFailure();
      }
    } catch (error) {
      this.handleFailure();
    } finally {
      this.isChecking = false;
    }
  }

  handleFailure() {
    this.consecutiveFailures++;
    console.warn(`[HealthCheck] ✗ Health check failed (${this.consecutiveFailures}/${this.failureThreshold})`);

    if (this.consecutiveFailures >= this.failureThreshold && !this.isTransitioning) {
      console.warn('[HealthCheck] Cluster transitioning detected - showing notification');

      // Mark as transitioning to suppress error messages
      this.isTransitioning = true;

      // Show notification
      this.showReloadNotification();

      // Keep the notification visible and let API retry logic handle the transition
      // Don't reload - GSLB will route to healthy cluster automatically
    }
  }

  showReloadNotification() {
    // Remove existing notification if any
    const existing = document.getElementById('cluster-transition-notification');
    if (existing) {
      existing.remove();
    }

    // Create notification
    const notification = document.createElement('div');
    notification.id = 'cluster-transition-notification';
    notification.style.cssText = `
      position: fixed;
      top: 20px;
      left: 50%;
      transform: translateX(-50%);
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
      padding: 16px 32px;
      border-radius: 12px;
      box-shadow: 0 8px 24px rgba(0,0,0,0.4);
      z-index: 10000;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      font-size: 15px;
      font-weight: 600;
      display: flex;
      align-items: center;
      gap: 12px;
      animation: slideDown 0.3s ease-out;
    `;

    // Add spinner
    const spinner = document.createElement('div');
    spinner.style.cssText = `
      width: 20px;
      height: 20px;
      border: 3px solid rgba(255,255,255,0.3);
      border-top-color: white;
      border-radius: 50%;
      animation: spin 1s linear infinite;
    `;

    notification.appendChild(spinner);

    const text = document.createElement('span');
    text.textContent = '클러스터 전환 중... 잠시만 기다려주세요.';
    notification.appendChild(text);

    // Add animations
    const style = document.createElement('style');
    style.textContent = `
      @keyframes slideDown {
        from {
          transform: translateX(-50%) translateY(-100%);
          opacity: 0;
        }
        to {
          transform: translateX(-50%) translateY(0);
          opacity: 1;
        }
      }
      @keyframes spin {
        to { transform: rotate(360deg); }
      }
    `;
    document.head.appendChild(style);

    document.body.appendChild(notification);
  }

  hideReloadNotification() {
    const notification = document.getElementById('cluster-transition-notification');
    if (notification) {
      notification.style.animation = 'slideUp 0.3s ease-out';
      setTimeout(() => notification.remove(), 300);
    }
  }

  start() {
    console.log('[HealthCheck] Starting health monitor...');

    // Initial check after 5 seconds
    setTimeout(() => {
      this.checkHealth();
    }, 5000);

    // Then check every interval
    this.intervalId = setInterval(() => {
      this.checkHealth();
    }, this.checkInterval);
  }

  stop() {
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
      console.log('[HealthCheck] Health monitor stopped');
    }
  }
}

// Export singleton instance
export const healthMonitor = new HealthMonitor({
  checkInterval: 5000,      // Check every 5 seconds
  failureThreshold: 2       // Reload after 2 consecutive failures (10 seconds)
});
