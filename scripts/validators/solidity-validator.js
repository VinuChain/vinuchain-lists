/**
 * Solidity source code validation utilities
 */

const { DANGEROUS_SOLIDITY_PATTERNS, MAX_SOLIDITY_FILE_SIZE } = require('../utils/constants');

/**
 * Check for dangerous Solidity patterns
 * @param {string} content - Solidity source code
 * @returns {string[]} Array of warnings about dangerous patterns found
 */
function checkDangerousPatterns(content) {
  const warnings = [];

  for (const [name, pattern] of Object.entries(DANGEROUS_SOLIDITY_PATTERNS)) {
    if (pattern.test(content)) {
      const messages = {
        selfdestruct: 'Contains selfdestruct - verify this is intentional and safe',
        suicide: 'Contains suicide (deprecated) - use selfdestruct if needed',
        delegatecall: 'Contains delegatecall - potential proxy vulnerability, ensure target is trusted',
        txOrigin: 'Uses tx.origin - authentication bypass risk, use msg.sender instead',
        blockhash: 'Uses blockhash - can be manipulated by miners',
        callcode: 'Contains callcode (deprecated) - use delegatecall if needed',
      };

      warnings.push(messages[name] || `Contains ${name} pattern`);
    }
  }

  return warnings;
}

/**
 * Validate basic Solidity file structure
 * @param {string} content - Solidity source code
 * @param {string} contractName - Expected contract name
 * @returns {{valid: boolean, error?: string, warnings?: string[]}} Validation result
 */
function validateSolidityStructure(content, contractName) {
  const warnings = [];

  // Check minimum content
  if (!content || content.trim().length === 0) {
    return { valid: false, error: 'Solidity file is empty' };
  }

  // Check file size
  if (content.length > MAX_SOLIDITY_FILE_SIZE) {
    return {
      valid: false,
      error: `Solidity file too large: ${content.length} bytes (max: ${MAX_SOLIDITY_FILE_SIZE})`,
    };
  }

  // Check for SPDX license
  if (!content.includes('// SPDX-License-Identifier:')) {
    warnings.push('Missing SPDX license identifier');
  }

  // Check for pragma directive
  if (!/pragma\s+solidity\s+[^;]+;/.test(content)) {
    return { valid: false, error: 'Missing pragma solidity directive' };
  }

  // Extract pragma version
  const pragmaMatch = content.match(/pragma\s+solidity\s+([^;]+);/);
  if (pragmaMatch) {
    const version = pragmaMatch[1].trim();

    // Warn about specific versions (should use range)
    if (/^[0-9]/.test(version) && !version.includes('^') && !version.includes('>')) {
      warnings.push(
        `Pragma uses exact version (${version}) - consider using range (e.g., ^0.8.0)`
      );
    }

    // Warn about old versions
    if (version.includes('0.4.') || version.includes('0.5.') || version.includes('0.6.')) {
      warnings.push(`Pragma uses old Solidity version (${version}) - consider upgrading`);
    }
  }

  // Check for contract declaration with the expected name
  const contractPatterns = [
    new RegExp(`contract\\s+${contractName}\\s*[{]`),
    new RegExp(`interface\\s+${contractName}\\s*[{]`),
    new RegExp(`library\\s+${contractName}\\s*[{]`),
    new RegExp(`abstract\\s+contract\\s+${contractName}\\s*[{]`),
  ];

  const hasDeclaration = contractPatterns.some(pattern => pattern.test(content));

  if (!hasDeclaration) {
    return {
      valid: false,
      error: `No declaration found for ${contractName} (expected contract, interface, library, or abstract contract)`,
    };
  }

  // Check for dangerous patterns
  const dangerousWarnings = checkDangerousPatterns(content);
  warnings.push(...dangerousWarnings);

  // Additional security checks
  if (/assembly\s*\{/.test(content)) {
    warnings.push('Contains inline assembly - ensure it\'s necessary and reviewed');
  }

  if (/\.call\s*\(/.test(content) || /\.callcode\s*\(/.test(content)) {
    warnings.push('Contains low-level call - ensure proper error handling and reentrancy protection');
  }

  if (/ecrecover\s*\(/.test(content)) {
    warnings.push('Uses ecrecover - ensure signature malleability is handled');
  }

  if (/transfer\s*\(/.test(content)) {
    warnings.push('Uses transfer() - consider using call() with value for better gas handling');
  }

  return { valid: true, warnings };
}

/**
 * Validate Solidity file for a contract
 * @param {string} content - Solidity source code
 * @param {string} contractName - Expected contract name
 * @returns {{valid: boolean, error?: string, warnings?: string[]}} Validation result
 */
function validateSolidityFile(content, contractName) {
  return validateSolidityStructure(content, contractName);
}

/**
 * Extract contract type from Solidity content
 * @param {string} content - Solidity source code
 * @param {string} contractName - Contract name to find
 * @returns {string|null} Contract type ('contract', 'interface', 'library', 'abstract') or null
 */
function extractContractType(content, contractName) {
  const patterns = {
    contract: new RegExp(`contract\\s+${contractName}\\s*[{]`),
    interface: new RegExp(`interface\\s+${contractName}\\s*[{]`),
    library: new RegExp(`library\\s+${contractName}\\s*[{]`),
    abstract: new RegExp(`abstract\\s+contract\\s+${contractName}\\s*[{]`),
  };

  for (const [type, pattern] of Object.entries(patterns)) {
    if (pattern.test(content)) {
      return type;
    }
  }

  return null;
}

module.exports = {
  checkDangerousPatterns,
  validateSolidityStructure,
  validateSolidityFile,
  extractContractType,
};
