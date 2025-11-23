/**
 * Unit tests for email-validator.js
 */

const { expect } = require('chai');
const {
  isValidEmailFormat,
  extractDomain,
  isDisposableEmail,
  isReservedEmail,
  validateEmail,
} = require('../../scripts/validators/email-validator');

describe('Email Validator', () => {
  describe('isValidEmailFormat', () => {
    it('should accept valid email formats', () => {
      expect(isValidEmailFormat('user@example.com')).to.be.true;
      expect(isValidEmailFormat('test.user@domain.co.uk')).to.be.true;
      expect(isValidEmailFormat('user+tag@example.com')).to.be.true;
    });

    it('should reject invalid formats', () => {
      expect(isValidEmailFormat('invalid')).to.be.false;
      expect(isValidEmailFormat('user@')).to.be.false;
      expect(isValidEmailFormat('@example.com')).to.be.false;
      expect(isValidEmailFormat('user @example.com')).to.be.false;
    });

    it('should reject non-string input', () => {
      expect(isValidEmailFormat(123)).to.be.false;
      expect(isValidEmailFormat(null)).to.be.false;
    });
  });

  describe('extractDomain', () => {
    it('should extract domain from email', () => {
      expect(extractDomain('user@example.com')).to.equal('example.com');
      expect(extractDomain('test@gmail.com')).to.equal('gmail.com');
    });

    it('should return null for invalid email', () => {
      expect(extractDomain('invalid')).to.be.null;
      expect(extractDomain('user@')).to.be.null;
    });

    it('should lowercase domain', () => {
      expect(extractDomain('user@EXAMPLE.COM')).to.equal('example.com');
    });
  });

  describe('isDisposableEmail', () => {
    it('should detect disposable email domains', () => {
      expect(isDisposableEmail('user@tempmail.com')).to.be.true;
      expect(isDisposableEmail('user@guerrillamail.com')).to.be.true;
      expect(isDisposableEmail('user@mailinator.com')).to.be.true;
    });

    it('should allow legitimate email domains', () => {
      expect(isDisposableEmail('user@gmail.com')).to.be.false;
      expect(isDisposableEmail('user@example.com')).to.be.false;
    });
  });

  describe('isReservedEmail', () => {
    it('should detect reserved domains', () => {
      expect(isReservedEmail('user@example.com')).to.be.true;
      expect(isReservedEmail('user@localhost')).to.be.true;
      expect(isReservedEmail('user@test.com')).to.be.true;
    });

    it('should allow legitimate domains', () => {
      expect(isReservedEmail('user@gmail.com')).to.be.false;
      expect(isReservedEmail('user@company.org')).to.be.false;
    });
  });

  describe('validateEmail', () => {
    it('should accept valid emails', () => {
      const result = validateEmail('user@gmail.com');
      expect(result.valid).to.be.true;
    });

    it('should reject invalid format', () => {
      const result = validateEmail('invalid-email');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('invalid format');
    });

    it('should reject disposable emails', () => {
      const result = validateEmail('user@tempmail.com');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('disposable');
    });

    it('should reject reserved domains', () => {
      const result = validateEmail('user@example.com');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('reserved');
    });

    it('should warn about common typos', () => {
      const result = validateEmail('user@gmail.co');
      expect(result.valid).to.be.true;
      expect(result.warnings).to.exist;
      expect(result.warnings[0]).to.include('gmail.com');
    });

    it('should include field name in errors', () => {
      const result = validateEmail('invalid', 'contact');
      expect(result.error).to.include('contact');
    });
  });
});
