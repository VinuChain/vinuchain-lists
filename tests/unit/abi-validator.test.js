/**
 * Unit tests for abi-validator.js
 */

const { expect } = require('chai');
const {
  validateABIParameter,
  validateABI,
} = require('../../scripts/validators/abi-validator');

describe('ABI Validator', () => {
  describe('validateABIParameter', () => {
    it('should accept valid parameter', () => {
      const param = { name: 'amount', type: 'uint256' };
      const result = validateABIParameter(param, 'test');
      expect(result.valid).to.be.true;
    });

    it('should accept parameter without name (outputs)', () => {
      const param = { type: 'uint256' };
      const result = validateABIParameter(param, 'test');
      expect(result.valid).to.be.true;
    });

    it('should reject missing type', () => {
      const param = { name: 'amount' };
      const result = validateABIParameter(param, 'test');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('missing \'type\' field');
    });

    it('should reject dangerous parameter names', () => {
      const dangerous = ['__proto__', 'constructor', 'prototype'];
      dangerous.forEach(name => {
        const param = { name, type: 'uint256' };
        const result = validateABIParameter(param, 'test');
        expect(result.valid).to.be.false;
        expect(result.error).to.include('not allowed');
      });
    });

    it('should reject invalid parameter names', () => {
      const param = { name: '../../malicious', type: 'uint256' };
      const result = validateABIParameter(param, 'test');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('invalid');
    });

    it('should handle tuple types with components', () => {
      const param = {
        name: 'data',
        type: 'tuple',
        components: [
          { name: 'field1', type: 'uint256' },
          { name: 'field2', type: 'address' },
        ],
      };
      const result = validateABIParameter(param, 'test');
      expect(result.valid).to.be.true;
    });
  });

  describe('validateABI', () => {
    it('should accept valid ABI', () => {
      const abi = [
        {
          type: 'constructor',
          inputs: [{ name: 'initialSupply', type: 'uint256' }],
        },
        {
          type: 'function',
          name: 'transfer',
          inputs: [
            { name: 'to', type: 'address' },
            { name: 'amount', type: 'uint256' },
          ],
          outputs: [{ name: '', type: 'bool' }],
          stateMutability: 'nonpayable',
        },
      ];
      const result = validateABI(abi, 'TestContract');
      expect(result.valid).to.be.true;
    });

    it('should reject non-array ABI', () => {
      const result = validateABI({}, 'TestContract');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('must be a JSON array');
    });

    it('should reject empty ABI', () => {
      const result = validateABI([], 'TestContract');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('empty');
    });

    it('should reject invalid ABI item types', () => {
      const abi = [{ type: 'malicious' }];
      const result = validateABI(abi, 'TestContract');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('invalid type');
    });

    it('should reject functions without name', () => {
      const abi = [{ type: 'function', inputs: [] }];
      const result = validateABI(abi, 'TestContract');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('missing \'name\' field');
    });

    it('should reject invalid state mutability', () => {
      const abi = [
        {
          type: 'function',
          name: 'test',
          inputs: [],
          outputs: [],
          stateMutability: 'invalid',
        },
      ];
      const result = validateABI(abi, 'TestContract');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('invalid stateMutability');
    });

    it('should include contract name in error messages', () => {
      const result = validateABI([], 'MyContract');
      expect(result.error).to.include('MyContract');
    });
  });
});
