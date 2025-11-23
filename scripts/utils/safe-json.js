/**
 * Safe JSON parsing utilities
 */

const fs = require('fs');
const path = require('path');
const { MAX_FILE_SIZE, EXIT_CODES } = require('./constants');

/**
 * Safely parse JSON with protection against prototype pollution
 * @param {string} text - JSON string to parse
 * @returns {Object} Parsed object with dangerous keys removed
 * @throws {SyntaxError} If JSON is invalid
 */
function safeParse(text) {
  // Parse with reviver function to block dangerous keys
  const obj = JSON.parse(text, (key, value) => {
    // Block prototype pollution keys
    if (key === '__proto__' || key === 'constructor' || key === 'prototype') {
      return undefined;
    }
    return value;
  });

  // Note: The reviver function above already blocks these keys, so these delete
  // operations are defensive redundancy. In practice, __proto__ cannot be deleted
  // (it's an accessor property), but we keep this as defense-in-depth.
  if (typeof obj === 'object' && obj !== null) {
    delete obj.__proto__;
    delete obj.constructor;
    delete obj.prototype;
  }

  return obj;
}

/**
 * Safely read and parse JSON file with size limits
 * @param {string} filePath - Path to JSON file
 * @param {number} maxSize - Maximum file size in bytes (default from constants)
 * @returns {Object} Parsed JSON object
 * @throws {Error} If file too large, missing, or invalid JSON
 */
function safeReadJSON(filePath, maxSize = MAX_FILE_SIZE) {
  // Check file exists
  if (!fs.existsSync(filePath)) {
    throw new Error(`File not found: ${filePath}`);
  }

  // Check file size before reading
  const stats = fs.statSync(filePath);
  if (stats.size > maxSize) {
    throw new Error(
      `File too large: ${stats.size} bytes (max: ${maxSize} bytes). File: ${filePath}`
    );
  }

  // Read file
  const content = fs.readFileSync(filePath, 'utf8');

  // Additional check: content length (in case size check was bypassed)
  if (content.length > maxSize) {
    throw new Error(`Content too large: ${content.length} bytes (max: ${maxSize})`);
  }

  // Parse safely with prototype pollution protection
  try {
    return safeParse(content);
  } catch (e) {
    if (e instanceof SyntaxError) {
      throw new Error(`Invalid JSON in ${path.basename(filePath)}: ${e.message}`);
    }
    throw e;
  }
}

/**
 * Load schema file with comprehensive error handling
 * @param {string} schemaPath - Path to schema file
 * @param {string} schemaName - Human-readable schema name for errors
 * @returns {Object} Parsed schema object
 * @throws {Error} Fatal error if schema cannot be loaded
 */
function loadSchema(schemaPath, schemaName) {
  try {
    if (!fs.existsSync(schemaPath)) {
      throw new Error(`Schema file not found: ${schemaPath}`);
    }

    const content = fs.readFileSync(schemaPath, 'utf8');
    const schema = safeParse(content);

    // Validate it's actually a schema object
    if (typeof schema !== 'object' || schema === null) {
      throw new Error('Schema must be an object');
    }

    return schema;
  } catch (e) {
    // Fatal error - cannot continue without schemas
    console.error(`\x1b[31mFATAL: Failed to load ${schemaName}\x1b[0m`);
    console.error(`Path: ${schemaPath}`);
    console.error(`Error: ${e.message}`);
    process.exit(EXIT_CODES.FATAL_ERROR);
  }
}

/**
 * Sanitize string for safe terminal output
 * Prevents terminal escape code injection
 * @param {string} str - String to sanitize
 * @returns {string} Sanitized string
 */
function sanitizeForTerminal(str) {
  if (typeof str !== 'string') return String(str);
  // Remove ANSI escape codes (e.g., \x1b[31m) and control characters
  return str
    .replace(/\x1b\[[0-9;]*m/g, '') // Remove ANSI color codes
    .replace(/[\x00-\x1F\x7F-\x9F]/g, ''); // Remove other control characters
}

module.exports = {
  safeParse,
  safeReadJSON,
  loadSchema,
  sanitizeForTerminal,
};
