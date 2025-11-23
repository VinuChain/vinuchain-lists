/**
 * Email validation utilities
 */

const { DISPOSABLE_EMAIL_DOMAINS, RESERVED_EMAIL_DOMAINS } = require('../utils/constants');

/**
 * Basic email format validation
 * @param {string} email - Email address to validate
 * @returns {boolean} True if format is valid
 */
function isValidEmailFormat(email) {
  if (typeof email !== 'string') return false;

  // Basic email regex (RFC 5322 simplified)
  const emailRegex = /^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/;

  return emailRegex.test(email);
}

/**
 * Extract domain from email address
 * @param {string} email - Email address
 * @returns {string|null} Domain part or null if invalid
 */
function extractDomain(email) {
  if (!isValidEmailFormat(email)) return null;

  const parts = email.split('@');
  if (parts.length !== 2) return null;

  return parts[1].toLowerCase();
}

/**
 * Check if email domain is disposable
 * @param {string} email - Email address
 * @returns {boolean} True if disposable domain
 */
function isDisposableEmail(email) {
  const domain = extractDomain(email);
  if (!domain) return false;

  return DISPOSABLE_EMAIL_DOMAINS.includes(domain);
}

/**
 * Check if email domain is reserved/invalid
 * @param {string} email - Email address
 * @returns {boolean} True if reserved domain
 */
function isReservedEmail(email) {
  const domain = extractDomain(email);
  if (!domain) return false;

  return RESERVED_EMAIL_DOMAINS.includes(domain);
}

/**
 * Validate email address comprehensively
 * @param {string} email - Email to validate
 * @param {string} fieldName - Field name for error messages
 * @returns {{valid: boolean, error?: string, warnings?: string[]}} Validation result
 */
function validateEmail(email, fieldName = 'email') {
  const warnings = [];

  // Check format
  if (!isValidEmailFormat(email)) {
    return { valid: false, error: `${fieldName} has invalid format` };
  }

  // Check for disposable email
  if (isDisposableEmail(email)) {
    return {
      valid: false,
      error: `${fieldName} uses disposable email service (not allowed)`,
    };
  }

  // Check for reserved domain
  if (isReservedEmail(email)) {
    return {
      valid: false,
      error: `${fieldName} uses reserved/test domain (not allowed)`,
    };
  }

  // Extract domain for additional checks
  const domain = extractDomain(email);

  // Warn about common typos in popular domains
  const commonTypos = {
    'gmail.co': 'gmail.com',
    'gmial.com': 'gmail.com',
    'gmai.com': 'gmail.com',
    'outlook.co': 'outlook.com',
    'hotmail.co': 'hotmail.com',
    'yahoo.co': 'yahoo.com',
  };

  if (commonTypos[domain]) {
    warnings.push(`Possible typo in domain: did you mean ${commonTypos[domain]}?`);
  }

  return { valid: true, warnings };
}

module.exports = {
  isValidEmailFormat,
  extractDomain,
  isDisposableEmail,
  isReservedEmail,
  validateEmail,
};
