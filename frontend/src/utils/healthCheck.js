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
        console.log('[HealthCheck] ✓ Cluster healthy');
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

    if (this.consecutiveFailures >= this.failureThreshold) {
      console.warn('[HealthCheck] Cluster may be transitioning. Relying on API retry logic instead of reload.');

      // DO NOT reload - let the fetch retry logic handle failover
      // This keeps the UI visible while services are transitioning

      // Reset counter after threshold to avoid log spam
      this.consecutiveFailures = 0;
    }
  }

  showReloadNotification() {
    // Create temporary notification
    const notification = document.createElement('div');
    notification.style.cssText = `
      position: fixed;
      top: 20px;
      left: 50%;
      transform: translateX(-50%);
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
      padding: 16px 24px;
      border-radius: 8px;
      box-shadow: 0 4px 12px rgba(0,0,0,0.3);
      z-index: 10000;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      font-size: 14px;
      font-weight: 500;
    `;
    notification.textContent = '클러스터 전환 중... 페이지를 새로고침합니다.';
    document.body.appendChild(notification);
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
