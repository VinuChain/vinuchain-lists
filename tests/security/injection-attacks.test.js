/**
 * Security tests for injection attack protection
 */

const { expect } = require('chai');
const { safeParse } = require('../../scripts/utils/safe-json');
const { sanitizeForTerminal } = require('../../scripts/utils/safe-json');
const { validateURL } = require('../../scripts/utils/url-validator');

describe('Injection Attack Protection', () => {
  describe('Prototype Pollution Protection', () => {
    it('should block __proto__ injection', () => {
      const malicious = '{"__proto__": {"polluted": true}}';
      const result = safeParse(malicious);

      // Check that global prototype is NOT polluted
      const testObj = {};
      expect(testObj.polluted).to.be.undefined;
    });

    it('should block constructor injection', () => {
      const malicious = '{"constructor": {"prototype": {"polluted": true}}}';
      safeParse(malicious);

      const testObj = {};
      expect(testObj.polluted).to.be.undefined;
    });

    it('should block prototype injection', () => {
      const malicious = '{"prototype": {"polluted": true}}';
      safeParse(malicious);

      const testObj = {};
      expect(testObj.polluted).to.be.undefined;
    });

    it('should block nested pollution attempts', () => {
      const malicious = '{"data": {"__proto__": {"polluted": true}}}';
      safeParse(malicious);

      const testObj = {};
      expect(testObj.polluted).to.be.undefined;
    });
  });

  describe('URL Injection Protection', () => {
    it('should block URLs with newline injection', () => {
      const malicious = 'https://example.com\nmalicious-code';
      const result = validateURL(malicious);
      expect(result.valid).to.be.false;
    });

    it('should block URLs with carriage return', () => {
      const malicious = 'https://example.com\rSet-Cookie: admin=true';
      const result = validateURL(malicious);
      expect(result.valid).to.be.false;
    });

    it('should block URLs with embedded JavaScript', () => {
      const malicious = 'https://example.com\njavascript:alert(1)';
      const result = validateURL(malicious);
      expect(result.valid).to.be.false;
    });
  });

  describe('Terminal Injection Protection', () => {
    it('should remove ANSI escape codes', () => {
      const malicious = '\x1b[31mRed\x1b[0m\x1b[32mGreen\x1b[0m';
      const result = sanitizeForTerminal(malicious);
      expect(result).to.equal('RedGreen');
    });

    it('should remove control characters', () => {
      const malicious = 'test\x00\x01\x02\x03\x04';
      const result = sanitizeForTerminal(malicious);
      expect(result).to.equal('test');
    });

    it('should remove terminal bell', () => {
      const malicious = 'test\x07';
      const result = sanitizeForTerminal(malicious);
      expect(result).to.equal('test');
    });
  });

  describe('ABI Injection Protection', () => {
    const { validateABI } = require('../../scripts/validators/abi-validator');

    it('should block __proto__ in parameter names', () => {
      const malicious = [
        {
          type: 'function',
          name: 'test',
          inputs: [{ name: '__proto__', type: 'uint256' }],
        },
      ];
      const result = validateABI(malicious, 'Test');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('not allowed');
    });

    it('should block constructor in parameter names', () => {
      const malicious = [
        {
          type: 'function',
          name: 'test',
          inputs: [{ name: 'constructor', type: 'uint256' }],
        },
      ];
      const result = validateABI(malicious, 'Test');
      expect(result.valid).to.be.false;
    });

    it('should block invalid function names', () => {
      const malicious = [
        {
          type: 'function',
          name: '../../malicious',
          inputs: [],
        },
      ];
      const result = validateABI(malicious, 'Test');
      expect(result.valid).to.be.false;
    });
  });
});
