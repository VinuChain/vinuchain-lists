/**
 * URL validation utilities with SSRF protection
 */

const {
  MAX_URL_LENGTH,
  URL_HTTPS_PATTERN,
  BLOCKED_HOSTS,
  BLOCKED_IP_PATTERNS,
} = require('./constants');

/**
 * Validate URL format (basic check)
 * @param {string} urlString - URL to validate
 * @returns {{valid: boolean, error?: string}} Validation result
 */
function validateURLFormat(urlString) {
  if (typeof urlString !== 'string') {
    return { valid: false, error: 'URL must be a string' };
  }

  // Check length
  if (urlString.length > MAX_URL_LENGTH) {
    return {
      valid: false,
      error: `URL too long: ${urlString.length} chars (max: ${MAX_URL_LENGTH})`,
    };
  }

  // Check for newlines
  if (/[\n\r]/.test(urlString)) {
    return { valid: false, error: 'URL contains newline characters' };
  }

  // Check for whitespace
  if (/\s/.test(urlString)) {
    return { valid: false, error: 'URL contains whitespace' };
  }

  // Validate HTTPS pattern
  if (!URL_HTTPS_PATTERN.test(urlString)) {
    return { valid: false, error: 'URL must start with https:// and be properly formatted' };
  }

  return { valid: true };
}

/**
 * Check if hostname is blocked for SSRF protection
 * @param {string} hostname - Hostname to check
 * @returns {boolean} True if hostname is blocked
 */
function isBlockedHost(hostname) {
  const lowerHostname = hostname.toLowerCase();

  // Check exact matches
  if (BLOCKED_HOSTS.includes(lowerHostname)) {
    return true;
  }

  // Check IP pattern matches
  for (const pattern of BLOCKED_IP_PATTERNS) {
    if (pattern.test(lowerHostname)) {
      return true;
    }
  }

  return false;
}

/**
 * Validate URL with SSRF protection
 * @param {string} urlString - URL to validate
 * @param {string} fieldName - Field name for error messages
 * @returns {{valid: boolean, error?: string}} Validation result
 */
function validateURL(urlString, fieldName = 'URL') {
  // Basic format validation
  const formatCheck = validateURLFormat(urlString);
  if (!formatCheck.valid) {
    return { valid: false, error: `${fieldName}: ${formatCheck.error}` };
  }

  try {
    const url = new URL(urlString);

    // Protocol must be HTTPS
    if (url.protocol !== 'https:') {
      return { valid: false, error: `${fieldName} must use HTTPS protocol` };
    }

    // Check for blocked hosts
    if (isBlockedHost(url.hostname)) {
      return {
        valid: false,
        error: `${fieldName} hostname is blocked (potential SSRF): ${url.hostname}`,
      };
    }

    // Check for unusual ports (potential port scanning)
    if (url.port && url.port !== '443') {
      return {
        valid: false,
        error: `${fieldName} uses non-standard HTTPS port: ${url.port}`,
      };
    }

    return { valid: true };
  } catch (e) {
    return { valid: false, error: `${fieldName} is not a valid URL: ${e.message}` };
  }
}

/**
 * Validate multiple URLs in an object
 * @param {Object} obj - Object containing URL fields
 * @param {string[]} urlFields - Array of field names that should contain URLs
 * @returns {{valid: boolean, errors: string[]}} Validation result with all errors
 */
function validateURLs(obj, urlFields) {
  const errors = [];

  for (const field of urlFields) {
    const value = obj[field];

    // Skip if field is not present (it may be optional)
    if (value === undefined || value === null) {
      continue;
    }

    // Validate the URL
    const result = validateURL(value, field);
    if (!result.valid) {
      errors.push(result.error);
    }
  }

  return {
    valid: errors.length === 0,
    errors,
  };
}

module.exports = {
  validateURLFormat,
  validateURL,
  validateURLs,
  isBlockedHost,
};
