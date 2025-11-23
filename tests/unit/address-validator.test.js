/**
 * Unit tests for address-validator.js
 */

const { expect } = require('chai');
const {
  isValidAddressFormat,
  validateEIP55Checksum,
  validateAddressDirectory,
  validateAddressMatchesDirectory,
  validateTokenAddress,
} = require('../../scripts/utils/address-validator');

describe('Address Validator', () => {
  describe('isValidAddressFormat', () => {
    it('should accept valid address format', () => {
      expect(isValidAddressFormat('0x00c1E515EA9579856304198EFb15f525A0bb50f6')).to.be.true;
      expect(isValidAddressFormat('0x0000000000000000000000000000000000000000')).to.be.true;
    });

    it('should reject invalid length', () => {
      expect(isValidAddressFormat('0x123')).to.be.false;
      expect(isValidAddressFormat('0x' + 'a'.repeat(41))).to.be.false;
    });

    it('should reject missing 0x prefix', () => {
      expect(isValidAddressFormat('00c1E515EA9579856304198EFb15f525A0bb50f6')).to.be.false;
    });

    it('should reject non-hex characters', () => {
      expect(isValidAddressFormat('0xGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG')).to.be.false;
    });

    it('should reject non-string input', () => {
      expect(isValidAddressFormat(123)).to.be.false;
      expect(isValidAddressFormat(null)).to.be.false;
      expect(isValidAddressFormat(undefined)).to.be.false;
    });
  });

  describe('validateEIP55Checksum', () => {
    it('should accept valid checksummed address', () => {
      const result = validateEIP55Checksum('0x00c1E515EA9579856304198EFb15f525A0bb50f6');
      expect(result.valid).to.be.true;
      expect(result.checksummed).to.equal('0x00c1E515EA9579856304198EFb15f525A0bb50f6');
    });

    it('should reject invalid checksum', () => {
      // Use an address that's valid format but wrong checksum (not zero address)
      const result = validateEIP55Checksum('0x5aAeb6053f3E94C9b9A09f33669435E7Ef1BeAed'); // Wrong checksum
      expect(result.valid).to.be.false;
      expect(result.error).to.exist;
      // For EIP-55 checksum errors specifically, ethers will fail during getAddress()
      // so we just verify it's rejected
    });

    it('should reject zero address', () => {
      const result = validateEIP55Checksum('0x0000000000000000000000000000000000000000');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('Zero address not allowed');
    });

    it('should reject invalid format', () => {
      const result = validateEIP55Checksum('0x123');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('Invalid address format');
    });

    it('should include context in error messages', () => {
      const result = validateEIP55Checksum('0x123', 'TestToken');
      expect(result.error).to.include('TestToken');
    });
  });

  describe('validateAddressDirectory', () => {
    it('should accept valid address directory', () => {
      const result = validateAddressDirectory(
        '0x00c1E515EA9579856304198EFb15f525A0bb50f6',
        process.cwd()
      );
      expect(result.valid).to.be.true;
    });

    it('should reject path traversal attempts', () => {
      const result = validateAddressDirectory('../../../etc/passwd', process.cwd());
      expect(result.valid).to.be.false;
      expect(result.error).to.include('Invalid address format');
    });

    it('should reject directory names with slashes', () => {
      const result = validateAddressDirectory('0x123/test', process.cwd());
      expect(result.valid).to.be.false;
    });

    it('should reject directory names with backslashes', () => {
      const result = validateAddressDirectory('0x123\\test', process.cwd());
      expect(result.valid).to.be.false;
    });

    it('should reject invalid address format', () => {
      const result = validateAddressDirectory('not-an-address', process.cwd());
      expect(result.valid).to.be.false;
    });
  });

  describe('validateAddressMatchesDirectory', () => {
    it('should accept matching address and directory', () => {
      const addr = '0x00c1E515EA9579856304198EFb15f525A0bb50f6';
      const result = validateAddressMatchesDirectory(addr, addr);
      expect(result.valid).to.be.true;
    });

    it('should reject mismatched address and directory', () => {
      const result = validateAddressMatchesDirectory(
        '0x00c1E515EA9579856304198EFb15f525A0bb50f6',
        '0x6109835364EdA2c43CaA8981681e75782C13566C'
      );
      expect(result.valid).to.be.false;
      expect(result.error).to.include('Address mismatch');
    });
  });
});
