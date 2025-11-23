/**
 * Ethereum address validation utilities
 */

const { getAddress } = require('ethers');
const path = require('path');
const { ADDRESS_PATTERN, ADDRESS_LENGTH } = require('./constants');

/**
 * Validate Ethereum address format (basic check)
 * @param {string} address - Address to validate
 * @returns {boolean} True if format is valid (0x + 40 hex chars)
 */
function isValidAddressFormat(address) {
  if (typeof address !== 'string') return false;
  if (address.length !== ADDRESS_LENGTH) return false;
  return ADDRESS_PATTERN.test(address);
}

/**
 * Validate EIP-55 checksum for Ethereum address
 * @param {string} address - Address to validate
 * @param {string} context - Context for error messages (e.g., token name)
 * @returns {{valid: boolean, checksummed?: string, error?: string}} Validation result
 */
function validateEIP55Checksum(address, context = 'address') {
  // First check basic format
  if (!isValidAddressFormat(address)) {
    return {
      valid: false,
      error: `Invalid address format for ${context}: must be 0x + 40 hex characters`,
    };
  }

  // Reject zero address
  if (address === '0x0000000000000000000000000000000000000000') {
    return {
      valid: false,
      error: `Zero address not allowed for ${context}`,
    };
  }

  try {
    // Use ethers.js to get properly checksummed address
    const checksummed = getAddress(address);

    // Compare with original
    if (address !== checksummed) {
      return {
        valid: false,
        checksummed,
        error: `Invalid EIP-55 checksum for ${context}: should be ${checksummed}`,
      };
    }

    return { valid: true, checksummed };
  } catch (e) {
    return {
      valid: false,
      error: `Invalid address for ${context}: ${e.message}`,
    };
  }
}

/**
 * Validate directory name is a safe Ethereum address
 * Prevents path traversal attacks
 * @param {string} dirName - Directory name to validate
 * @param {string} parentPath - Parent directory path
 * @returns {{valid: boolean, error?: string}} Validation result
 */
function validateAddressDirectory(dirName, parentPath) {
  // Must be valid address format
  if (!isValidAddressFormat(dirName)) {
    return {
      valid: false,
      error: `Invalid address format in directory name: ${dirName}`,
    };
  }

  // Check for path traversal characters
  if (dirName.includes('..') || dirName.includes('/') || dirName.includes('\\')) {
    return {
      valid: false,
      error: `Path traversal detected in directory name: ${dirName}`,
    };
  }

  // Verify resolved path stays within parent directory
  const fullPath = path.join(parentPath, dirName);
  const resolvedPath = path.resolve(fullPath);
  const resolvedParent = path.resolve(parentPath);

  if (!resolvedPath.startsWith(resolvedParent + path.sep)) {
    return {
      valid: false,
      error: `Directory escapes parent path: ${dirName}`,
    };
  }

  return { valid: true };
}

/**
 * Validate address matches expected directory name
 * @param {string} address - Address from JSON file
 * @param {string} dirName - Directory name
 * @returns {{valid: boolean, error?: string}} Validation result
 */
function validateAddressMatchesDirectory(address, dirName) {
  if (address !== dirName) {
    return {
      valid: false,
      error: `Address mismatch: directory is ${dirName}, but address field is ${address}`,
    };
  }
  return { valid: true };
}

/**
 * Full address validation pipeline
 * @param {string} address - Address to validate
 * @param {string} dirName - Directory name
 * @param {string} context - Context for errors
 * @returns {{valid: boolean, checksummed?: string, error?: string}} Validation result
 */
function validateTokenAddress(address, dirName, context) {
  // 1. Validate directory name is safe
  const dirValidation = validateAddressDirectory(dirName, path.dirname(path.dirname(__filename)));
  if (!dirValidation.valid) {
    return dirValidation;
  }

  // 2. Validate EIP-55 checksum
  const checksumValidation = validateEIP55Checksum(address, context);
  if (!checksumValidation.valid) {
    return checksumValidation;
  }

  // 3. Validate address matches directory
  const matchValidation = validateAddressMatchesDirectory(address, dirName);
  if (!matchValidation.valid) {
    return matchValidation;
  }

  return { valid: true, checksummed: checksumValidation.checksummed };
}

module.exports = {
  isValidAddressFormat,
  validateEIP55Checksum,
  validateAddressDirectory,
  validateAddressMatchesDirectory,
  validateTokenAddress,
};
