/**
 * Unit tests for file-utils.js
 */

const { expect } = require('chai');
const {
  validateSafeFilename,
  validateContractName,
  safePathJoin,
} = require('../../scripts/utils/file-utils');

describe('File Utils', () => {
  describe('validateSafeFilename', () => {
    it('should accept safe filenames', () => {
      expect(validateSafeFilename('test.json').valid).to.be.true;
      expect(validateSafeFilename('Factory.sol').valid).to.be.true;
      expect(validateSafeFilename('contract_abi.json').valid).to.be.true;
    });

    it('should reject path traversal attempts', () => {
      expect(validateSafeFilename('../../../etc/passwd').valid).to.be.false;
      expect(validateSafeFilename('..\\..\\windows\\system32').valid).to.be.false;
    });

    it('should reject null bytes', () => {
      const result = validateSafeFilename('test\x00.txt');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('null byte');
    });

    it('should reject control characters', () => {
      const result = validateSafeFilename('test\x01.txt');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('control characters');
    });

    it('should reject non-string input', () => {
      expect(validateSafeFilename(123).valid).to.be.false;
      expect(validateSafeFilename(null).valid).to.be.false;
    });
  });

  describe('validateContractName', () => {
    it('should accept valid PascalCase names', () => {
      expect(validateContractName('Factory').valid).to.be.true;
      expect(validateContractName('TokenController').valid).to.be.true;
      expect(validateContractName('ERC20Token').valid).to.be.true;
    });

    it('should reject lowercase names', () => {
      expect(validateContractName('factory').valid).to.be.false;
      expect(validateContractName('tokenController').valid).to.be.false;
    });

    it('should reject names with special characters', () => {
      expect(validateContractName('Factory-v2').valid).to.be.false;
      expect(validateContractName('Factory_v2').valid).to.be.false;
      expect(validateContractName('Factory.sol').valid).to.be.false;
    });

    it('should reject path traversal attempts', () => {
      const result = validateContractName('../../../etc/passwd');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('Invalid contract name');
    });

    it('should reject empty names', () => {
      expect(validateContractName('').valid).to.be.false;
    });

    it('should reject non-string input', () => {
      expect(validateContractName(123).valid).to.be.false;
    });
  });

  describe('safePathJoin', () => {
    it('should safely join paths', () => {
      const result = safePathJoin('/base', 'subdir', 'file.txt');
      expect(result.valid).to.be.true;
      expect(result.path).to.include('subdir');
      expect(result.path).to.include('file.txt');
    });

    it('should reject path traversal in parts', () => {
      const result = safePathJoin('/base', '../../../etc', 'passwd');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('traversal');
    });

    it('should verify path stays within base', () => {
      const result = safePathJoin('/base', '..', 'outside');
      expect(result.valid).to.be.false;
    });

    it('should handle single part', () => {
      const result = safePathJoin('/base', 'file.txt');
      expect(result.valid).to.be.true;
    });
  });
});
