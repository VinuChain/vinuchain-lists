/**
 * Safe file operation utilities
 */

const fs = require('fs');
const path = require('path');
const { SAFE_CONTRACT_NAME_PATTERN } = require('./constants');

/**
 * Validate filename is safe (no path traversal)
 * @param {string} filename - Filename to validate
 * @returns {{valid: boolean, error?: string}} Validation result
 */
function validateSafeFilename(filename) {
  if (typeof filename !== 'string') {
    return { valid: false, error: 'Filename must be a string' };
  }

  // Check for path traversal
  if (filename.includes('..') || filename.includes('/') || filename.includes('\\')) {
    return { valid: false, error: `Path traversal detected in filename: ${filename}` };
  }

  // Check for null bytes
  if (filename.includes('\0')) {
    return { valid: false, error: 'Filename contains null byte' };
  }

  // Check for control characters
  if (/[\x00-\x1F\x7F]/.test(filename)) {
    return { valid: false, error: 'Filename contains control characters' };
  }

  return { valid: true };
}

/**
 * Validate contract name for safety
 * @param {string} contractName - Contract name to validate
 * @returns {{valid: boolean, error?: string}} Validation result
 */
function validateContractName(contractName) {
  if (typeof contractName !== 'string') {
    return { valid: false, error: 'Contract name must be a string' };
  }

  if (!SAFE_CONTRACT_NAME_PATTERN.test(contractName)) {
    return {
      valid: false,
      error: `Invalid contract name: ${contractName}. Must be PascalCase alphanumeric.`,
    };
  }

  return { valid: true };
}

/**
 * Safely construct file path and verify it's within allowed directory
 * @param {string} baseDir - Base directory path
 * @param {...string} parts - Path parts to join
 * @returns {{valid: boolean, path?: string, error?: string}} Validation result
 */
function safePathJoin(baseDir, ...parts) {
  try {
    // Validate each part
    for (const part of parts) {
      const validation = validateSafeFilename(part);
      if (!validation.valid) {
        return validation;
      }
    }

    // Construct path
    const fullPath = path.join(baseDir, ...parts);

    // Resolve to absolute paths
    const resolvedPath = path.resolve(fullPath);
    const resolvedBase = path.resolve(baseDir);

    // Verify path is within base directory
    if (!resolvedPath.startsWith(resolvedBase + path.sep) && resolvedPath !== resolvedBase) {
      return {
        valid: false,
        error: `Path escapes base directory: ${parts.join('/')}`,
      };
    }

    return { valid: true, path: fullPath };
  } catch (e) {
    return { valid: false, error: `Path construction failed: ${e.message}` };
  }
}

/**
 * Check if file exists and is readable
 * Uses single operation to avoid race condition
 * @param {string} filePath - Path to check
 * @returns {{exists: boolean, readable: boolean, error?: string}} Check result
 */
function checkFileAccess(filePath) {
  try {
    fs.accessSync(filePath, fs.constants.R_OK);
    return { exists: true, readable: true };
  } catch (e) {
    if (e.code === 'ENOENT') {
      return { exists: false, readable: false };
    }
    return { exists: true, readable: false, error: e.message };
  }
}

/**
 * Safely read file with existence check in single operation
 * Avoids TOCTOU race condition
 * @param {string} filePath - Path to read
 * @param {string} encoding - File encoding (default: utf8)
 * @returns {{success: boolean, content?: string, error?: string}} Read result
 */
function safeReadFile(filePath, encoding = 'utf8') {
  try {
    const content = fs.readFileSync(filePath, encoding);
    return { success: true, content };
  } catch (e) {
    if (e.code === 'ENOENT') {
      return { success: false, error: `File not found: ${path.basename(filePath)}` };
    } else if (e.code === 'EACCES') {
      return { success: false, error: `Permission denied: ${path.basename(filePath)}` };
    } else {
      return { success: false, error: `Error reading file: ${e.message}` };
    }
  }
}

/**
 * Get directory entries with error handling
 * @param {string} dirPath - Directory to read
 * @returns {{success: boolean, entries?: string[], error?: string}} Read result
 */
function safeReadDir(dirPath) {
  try {
    const entries = fs.readdirSync(dirPath);
    return { success: true, entries };
  } catch (e) {
    if (e.code === 'ENOENT') {
      return { success: false, error: `Directory not found: ${path.basename(dirPath)}` };
    } else if (e.code === 'EACCES') {
      return { success: false, error: `Permission denied: ${path.basename(dirPath)}` };
    } else {
      return { success: false, error: `Error reading directory: ${e.message}` };
    }
  }
}

/**
 * Check if path is a directory
 * @param {string} dirPath - Path to check
 * @returns {boolean} True if path is a directory
 */
function isDirectory(dirPath) {
  try {
    const stats = fs.statSync(dirPath);
    return stats.isDirectory();
  } catch {
    return false;
  }
}

module.exports = {
  validateSafeFilename,
  validateContractName,
  safePathJoin,
  checkFileAccess,
  safeReadFile,
  safeReadDir,
  isDirectory,
};
