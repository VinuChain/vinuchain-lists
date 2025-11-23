/**
 * ABI validation utilities
 */

const {
  VALID_ABI_TYPES,
  VALID_STATE_MUTABILITY,
  ABI_FUNCTION_NAME_PATTERN,
} = require('../utils/constants');

/**
 * Validate ABI parameter object
 * @param {Object} param - Parameter object from ABI
 * @param {string} context - Context for error messages
 * @returns {{valid: boolean, error?: string}} Validation result
 */
function validateABIParameter(param, context) {
  if (typeof param !== 'object' || param === null) {
    return { valid: false, error: `${context}: parameter must be an object` };
  }

  // Must have type
  if (!param.type || typeof param.type !== 'string') {
    return { valid: false, error: `${context}: parameter missing 'type' field` };
  }

  // Name is optional for outputs in Solidity ABIs
  if (param.name !== undefined && param.name !== '' && typeof param.name !== 'string') {
    return { valid: false, error: `${context}: parameter name must be a string` };
  }

  // Validate parameter name if present
  if (param.name && param.name !== '') {
    if (!ABI_FUNCTION_NAME_PATTERN.test(param.name)) {
      return {
        valid: false,
        error: `${context}: parameter name '${param.name}' is invalid (must be valid identifier)`,
      };
    }

    // Check for dangerous parameter names
    const dangerousNames = ['__proto__', 'constructor', 'prototype'];
    if (dangerousNames.includes(param.name)) {
      return {
        valid: false,
        error: `${context}: parameter name '${param.name}' is not allowed (security risk)`,
      };
    }
  }

  // Validate type format (basic check)
  if (!/^[a-zA-Z0-9[\](),\s]+$/.test(param.type)) {
    return {
      valid: false,
      error: `${context}: parameter type '${param.type}' contains invalid characters`,
    };
  }

  // For tuple types, validate components
  if (param.type.startsWith('tuple') && param.components) {
    if (!Array.isArray(param.components)) {
      return { valid: false, error: `${context}: tuple components must be an array` };
    }

    for (let i = 0; i < param.components.length; i++) {
      const componentResult = validateABIParameter(
        param.components[i],
        `${context}.components[${i}]`
      );
      if (!componentResult.valid) {
        return componentResult;
      }
    }
  }

  return { valid: true };
}

/**
 * Validate array of ABI parameters (inputs/outputs)
 * @param {Array} params - Array of parameters
 * @param {string} context - Context for error messages
 * @returns {{valid: boolean, error?: string}} Validation result
 */
function validateABIParameters(params, context) {
  if (!Array.isArray(params)) {
    return { valid: false, error: `${context} must be an array` };
  }

  for (let i = 0; i < params.length; i++) {
    const result = validateABIParameter(params[i], `${context}[${i}]`);
    if (!result.valid) {
      return result;
    }
  }

  return { valid: true };
}

/**
 * Validate single ABI item
 * @param {Object} item - ABI item to validate
 * @param {number} index - Index in ABI array
 * @returns {{valid: boolean, error?: string, warnings?: string[]}} Validation result
 */
function validateABIItem(item, index) {
  const warnings = [];

  // Must be an object
  if (typeof item !== 'object' || item === null) {
    return { valid: false, error: `ABI item ${index} must be an object` };
  }

  // Must have type field
  if (!item.type || typeof item.type !== 'string') {
    return { valid: false, error: `ABI item ${index} missing 'type' field` };
  }

  // Validate type
  if (!VALID_ABI_TYPES.includes(item.type)) {
    return {
      valid: false,
      error: `ABI item ${index} has invalid type: ${item.type}`,
    };
  }

  // Functions, events, and errors must have a name
  if (['function', 'event', 'error'].includes(item.type)) {
    if (!item.name || typeof item.name !== 'string') {
      return {
        valid: false,
        error: `ABI item ${index} (${item.type}) missing 'name' field`,
      };
    }

    // Validate name format
    if (!ABI_FUNCTION_NAME_PATTERN.test(item.name)) {
      return {
        valid: false,
        error: `ABI item ${index} has invalid name: ${item.name}`,
      };
    }
  }

  // Functions and constructors should have inputs
  if (['function', 'constructor'].includes(item.type)) {
    if (!item.inputs) {
      warnings.push(`ABI item ${index} (${item.type}) missing 'inputs' field`);
    } else {
      const inputsResult = validateABIParameters(
        item.inputs,
        `ABI item ${index}.inputs`
      );
      if (!inputsResult.valid) {
        return inputsResult;
      }
    }
  }

  // Functions should have outputs
  if (item.type === 'function') {
    if (!item.outputs) {
      warnings.push(`ABI item ${index} (function ${item.name}) missing 'outputs' field`);
    } else {
      const outputsResult = validateABIParameters(
        item.outputs,
        `ABI item ${index}.outputs`
      );
      if (!outputsResult.valid) {
        return outputsResult;
      }
    }
  }

  // Validate stateMutability if present
  if (item.stateMutability) {
    if (!VALID_STATE_MUTABILITY.includes(item.stateMutability)) {
      return {
        valid: false,
        error: `ABI item ${index} has invalid stateMutability: ${item.stateMutability}`,
      };
    }
  }

  // Events should have inputs
  if (item.type === 'event') {
    if (!item.inputs) {
      warnings.push(`ABI item ${index} (event ${item.name}) missing 'inputs' field`);
    } else {
      const inputsResult = validateABIParameters(
        item.inputs,
        `ABI item ${index}.inputs`
      );
      if (!inputsResult.valid) {
        return inputsResult;
      }
    }
  }

  return { valid: true, warnings };
}

/**
 * Validate complete ABI array
 * @param {Array} abi - ABI to validate
 * @param {string} contractName - Contract name for error messages
 * @returns {{valid: boolean, error?: string, warnings?: string[]}} Validation result
 */
function validateABI(abi, contractName = 'contract') {
  const allWarnings = [];

  // Must be an array
  if (!Array.isArray(abi)) {
    return { valid: false, error: `ABI for ${contractName} must be a JSON array` };
  }

  // Should not be empty
  if (abi.length === 0) {
    return { valid: false, error: `ABI for ${contractName} is empty` };
  }

  // Validate each item
  for (let i = 0; i < abi.length; i++) {
    const result = validateABIItem(abi[i], i);
    if (!result.valid) {
      return {
        valid: false,
        error: `${contractName}: ${result.error}`,
      };
    }
    if (result.warnings && result.warnings.length > 0) {
      allWarnings.push(...result.warnings.map(w => `${contractName}: ${w}`));
    }
  }

  // Check for basic completeness
  const hasConstructor = abi.some(item => item.type === 'constructor');
  const hasFunctions = abi.some(item => item.type === 'function');

  if (!hasConstructor && !hasFunctions) {
    allWarnings.push(
      `${contractName}: ABI has no constructor or functions (may be interface/library)`
    );
  }

  return { valid: true, warnings: allWarnings };
}

module.exports = {
  validateABIParameter,
  validateABIParameters,
  validateABIItem,
  validateABI,
};
