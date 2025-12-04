/**
 * Fetch with automatic retry and exponential backoff
 * Useful for handling temporary network failures during failover/failback scenarios
 */
export async function fetchWithRetry(url, options = {}, retries = 5) {
  const {
    timeout = 15000, // 15 seconds timeout (increased for cluster transitions)
    retryDelay = 2000, // Start with 2 second delay
    ...fetchOptions
  } = options;

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

      // For 5xx errors, retry
      console.warn(`Attempt ${attempt + 1} failed with status ${response.status}, retrying...`);

    } catch (error) {
      const isLastAttempt = attempt === retries;

      if (isLastAttempt) {
        console.error(`All ${retries + 1} attempts failed:`, error);
        throw error;
      }

      // Exponential backoff: 1s, 2s, 4s, 8s...
      const delay = retryDelay * Math.pow(2, attempt);
      console.warn(`Attempt ${attempt + 1} failed, retrying in ${delay}ms...`);

      await new Promise(resolve => setTimeout(resolve, delay));
    }
  }
}
