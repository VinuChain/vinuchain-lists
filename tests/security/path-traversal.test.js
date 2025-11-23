/**
 * Security tests for path traversal protection
 */

const { expect } = require('chai');
const { validateContractName } = require('../../scripts/utils/file-utils');
const { validateAddressDirectory } = require('../../scripts/utils/address-validator');

describe('Path Traversal Security Tests', () => {
  describe('Contract Name Path Traversal', () => {
    const pathTraversalAttempts = [
      '../../../etc/passwd',
      '..\\..\\..\\windows\\system32',
      '../../../../root/.ssh/id_rsa',
      '../../../var/www/config.php',
      '..%2F..%2F..%2Fetc%2Fpasswd',
      'test/../../etc/passwd',
      'test\\..\\..\\etc\\passwd',
    ];

    pathTraversalAttempts.forEach(attempt => {
      it(`should block: ${attempt}`, () => {
        const result = validateContractName(attempt);
        expect(result.valid).to.be.false;
        expect(result.error).to.exist;
      });
    });

    it('should allow legitimate contract names', () => {
      const legitimate = ['Factory', 'Router', 'TokenController', 'ERC20'];
      legitimate.forEach(name => {
        const result = validateContractName(name);
        expect(result.valid, `${name} should be valid`).to.be.true;
      });
    });
  });

  describe('Token Directory Path Traversal', () => {
    const pathTraversalAttempts = [
      '0x../../etc/passwd',
      '0x..\\..\\windows\\system32',
      '../0x00c1E515EA9579856304198EFb15f525A0bb50f6',
      '0x00c1E515EA9579856304198EFb15f525A0bb50f6/../../../etc',
    ];

    pathTraversalAttempts.forEach(attempt => {
      it(`should block: ${attempt}`, () => {
        const result = validateAddressDirectory(attempt, process.cwd());
        expect(result.valid).to.be.false;
        expect(result.error).to.exist;
      });
    });

    it('should allow valid Ethereum addresses', () => {
      const result = validateAddressDirectory(
        '0x00c1E515EA9579856304198EFb15f525A0bb50f6',
        process.cwd()
      );
      expect(result.valid).to.be.true;
    });
  });

  describe('Null Byte Injection', () => {
    it('should block filenames with null bytes', () => {
      const { validateSafeFilename } = require('../../scripts/utils/file-utils');
      const result = validateSafeFilename('test\x00.txt');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('null byte');
    });
  });

  describe('Control Character Injection', () => {
    it('should block filenames with control characters', () => {
      const { validateSafeFilename } = require('../../scripts/utils/file-utils');
      const result = validateSafeFilename('test\x01\x02\x03.txt');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('control characters');
    });
  });
});
