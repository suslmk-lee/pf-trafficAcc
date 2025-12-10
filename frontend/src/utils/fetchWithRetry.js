/**
 * Fetch with automatic retry and exponential backoff
 * Useful for handling temporary network failures during failover/failback scenarios
 *
 * Timeline for cluster failover (10 retries):
 * 3s, 6s, 12s, 24s, 30s, 30s, 30s, 30s, 30s, 30s
 * Total: ~225 seconds (3.75 minutes)
 */
import { healthMonitor } from './healthCheck';

export async function fetchWithRetry(url, options = {}, retries = 10) {
  const {
    timeout = 20000, // 20 seconds timeout (increased for cluster transitions)
    retryDelay = 3000, // Start with 3 second delay
    maxRetryDelay = 30000, // Cap maximum delay at 30 seconds
    ...fetchOptions
  } = options;

  let firstFailure = true;

  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      // Create timeout promise
      const timeoutPromise = new Promise((_, reject) =>
        setTimeout(() => reject(new Error('Request timeout')), timeout)
      );

      // Race between fetch and timeout
      const response = await Promise.race([
        fetch(url, fetchOptions),
        timeoutPromise
      ]);

      // If response is ok, return it
      if (response.ok) {
        return response;
      }

      // If it's a 4xx error (client error), don't retry
      if (response.status >= 400 && response.status < 500) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      // For 5xx errors, trigger transition on first failure and retry
      if (firstFailure && attempt > 0) {
        console.warn('[FetchWithRetry] First 5xx error detected - triggering transition notification');
        healthMonitor.triggerTransition();
        firstFailure = false;
      }

      console.warn(`Attempt ${attempt + 1} failed with status ${response.status}, retrying...`);

    } catch (error) {
      const isLastAttempt = attempt === retries;

      // On first failure, trigger cluster transition notification
      if (firstFailure && attempt > 0) {
        console.warn('[FetchWithRetry] First API failure detected - triggering transition notification');
        healthMonitor.triggerTransition();
        firstFailure = false;
      }

      if (isLastAttempt) {
        console.error(`All ${retries + 1} attempts failed:`, error);
        throw error;
      }

      // Exponential backoff with cap: 3s, 6s, 12s, 24s, 30s (max)...
      const delay = Math.min(retryDelay * Math.pow(2, attempt), maxRetryDelay);
      console.warn(`Attempt ${attempt + 1}/${retries + 1} failed, retrying in ${delay / 1000}s...`);

      await new Promise(resolve => setTimeout(resolve, delay));
    }
  }
}
