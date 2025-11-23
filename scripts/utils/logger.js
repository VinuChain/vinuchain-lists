/**
 * Structured logging utility
 */

const { COLORS, LOG_LEVELS } = require('./constants');
const { sanitizeForTerminal } = require('./safe-json');

// Global counters
let errorCount = 0;
let warningCount = 0;
let infoCount = 0;

// Log format: 'human' or 'json'
const logFormat = process.env.LOG_FORMAT || 'human';

/**
 * Icons for different log levels
 */
const ICONS = {
  [LOG_LEVELS.ERROR]: '❌',
  [LOG_LEVELS.WARN]: '⚠️ ',
  [LOG_LEVELS.INFO]: 'ℹ️ ',
  [LOG_LEVELS.SUCCESS]: '✅',
  [LOG_LEVELS.DEBUG]: '🔍',
};

/**
 * Base logging function
 * @param {string} level - Log level
 * @param {string} message - Log message
 * @param {Object} metadata - Additional metadata
 */
function log(level, message, metadata = {}) {
  // Sanitize message for terminal output
  const sanitizedMessage = sanitizeForTerminal(message);

  if (logFormat === 'json') {
    // JSON output for machine parsing
    const logEntry = {
      timestamp: new Date().toISOString(),
      level,
      message: sanitizedMessage,
      ...metadata,
    };
    console.log(JSON.stringify(logEntry));
  } else {
    // Human-readable output
    const color = COLORS[levelToColor(level)] || COLORS.RESET;
    const icon = ICONS[level] || '';
    console.log(`${color}${icon} ${sanitizedMessage}${COLORS.RESET}`);

    // Log metadata if present
    if (Object.keys(metadata).length > 0) {
      console.log(`${COLORS.CYAN}  Metadata: ${JSON.stringify(metadata)}${COLORS.RESET}`);
    }
  }
}

/**
 * Map log level to color
 * @param {string} level - Log level
 * @returns {string} Color name
 */
function levelToColor(level) {
  switch (level) {
    case LOG_LEVELS.ERROR:
      return 'RED';
    case LOG_LEVELS.WARN:
      return 'YELLOW';
    case LOG_LEVELS.INFO:
      return 'BLUE';
    case LOG_LEVELS.SUCCESS:
      return 'GREEN';
    case LOG_LEVELS.DEBUG:
      return 'CYAN';
    default:
      return 'RESET';
  }
}

/**
 * Log error message and increment counter
 * @param {string} message - Error message
 * @param {Object} metadata - Additional metadata
 */
function error(message, metadata = {}) {
  log(LOG_LEVELS.ERROR, message, metadata);
  errorCount++;
}

/**
 * Log warning message and increment counter
 * @param {string} message - Warning message
 * @param {Object} metadata - Additional metadata
 */
function warn(message, metadata = {}) {
  log(LOG_LEVELS.WARN, message, metadata);
  warningCount++;
}

/**
 * Log info message and increment counter
 * @param {string} message - Info message
 * @param {Object} metadata - Additional metadata
 */
function info(message, metadata = {}) {
  log(LOG_LEVELS.INFO, message, metadata);
  infoCount++;
}

/**
 * Log success message
 * @param {string} message - Success message
 * @param {Object} metadata - Additional metadata
 */
function success(message, metadata = {}) {
  log(LOG_LEVELS.SUCCESS, message, metadata);
}

/**
 * Log debug message
 * @param {string} message - Debug message
 * @param {Object} metadata - Additional metadata
 */
function debug(message, metadata = {}) {
  if (process.env.DEBUG) {
    log(LOG_LEVELS.DEBUG, message, metadata);
  }
}

/**
 * Log section header
 * @param {string} title - Section title
 */
function section(title) {
  const sanitized = sanitizeForTerminal(title);
  if (logFormat === 'json') {
    log(LOG_LEVELS.INFO, sanitized, { type: 'section' });
  } else {
    console.log(`\n${COLORS.MAGENTA}${'='.repeat(60)}${COLORS.RESET}`);
    console.log(`${COLORS.MAGENTA}${sanitized}${COLORS.RESET}`);
    console.log(`${COLORS.MAGENTA}${'='.repeat(60)}${COLORS.RESET}\n`);
  }
}

/**
 * Log validation summary
 */
function summary() {
  section('Validation Summary');

  const total = errorCount + warningCount;

  if (logFormat === 'json') {
    log(LOG_LEVELS.INFO, 'Validation complete', {
      errors: errorCount,
      warnings: warningCount,
      info: infoCount,
      total,
    });
  } else {
    console.log(`${COLORS.BLUE}Total issues: ${total}${COLORS.RESET}`);
    console.log(`  ${COLORS.RED}Errors: ${errorCount}${COLORS.RESET}`);
    console.log(`  ${COLORS.YELLOW}Warnings: ${warningCount}${COLORS.RESET}`);
    console.log(`  ${COLORS.CYAN}Info: ${infoCount}${COLORS.RESET}`);
  }
}

/**
 * Get current counters
 * @returns {{errors: number, warnings: number, info: number}} Counters
 */
function getCounters() {
  return {
    errors: errorCount,
    warnings: warningCount,
    info: infoCount,
  };
}

/**
 * Reset all counters
 */
function resetCounters() {
  errorCount = 0;
  warningCount = 0;
  infoCount = 0;
}

module.exports = {
  error,
  warn,
  info,
  success,
  debug,
  section,
  summary,
  getCounters,
  resetCounters,
};
