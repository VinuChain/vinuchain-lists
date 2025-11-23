/**
 * Unit tests for url-validator.js
 */

const { expect } = require('chai');
const {
  validateURLFormat,
  validateURL,
  validateURLs,
  isBlockedHost,
} = require('../../scripts/utils/url-validator');

describe('URL Validator', () => {
  describe('validateURLFormat', () => {
    it('should accept valid HTTPS URLs', () => {
      expect(validateURLFormat('https://example.com').valid).to.be.true;
      expect(validateURLFormat('https://github.com/user/repo').valid).to.be.true;
    });

    it('should reject non-HTTPS URLs', () => {
      expect(validateURLFormat('http://example.com').valid).to.be.false;
      expect(validateURLFormat('ftp://example.com').valid).to.be.false;
    });

    it('should reject URLs with newlines', () => {
      const result = validateURLFormat('https://example.com\nmalicious');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('newline');
    });

    it('should reject URLs with whitespace', () => {
      const result = validateURLFormat('https://example.com with space');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('whitespace');
    });

    it('should reject URLs that are too long', () => {
      const longUrl = 'https://example.com/' + 'a'.repeat(500);
      const result = validateURLFormat(longUrl);
      expect(result.valid).to.be.false;
      expect(result.error).to.include('too long');
    });

    it('should reject non-string input', () => {
      expect(validateURLFormat(123).valid).to.be.false;
      expect(validateURLFormat(null).valid).to.be.false;
    });
  });

  describe('isBlockedHost', () => {
    it('should block localhost', () => {
      expect(isBlockedHost('localhost')).to.be.true;
      expect(isBlockedHost('LOCALHOST')).to.be.true;
    });

    it('should block 127.0.0.1', () => {
      expect(isBlockedHost('127.0.0.1')).to.be.true;
    });

    it('should block AWS metadata endpoint', () => {
      expect(isBlockedHost('169.254.169.254')).to.be.true;
    });

    it('should block GCP metadata endpoint', () => {
      expect(isBlockedHost('metadata.google.internal')).to.be.true;
    });

    it('should block private IP ranges', () => {
      expect(isBlockedHost('10.0.0.1')).to.be.true;
      expect(isBlockedHost('172.16.0.1')).to.be.true;
      expect(isBlockedHost('192.168.1.1')).to.be.true;
    });

    it('should block IPv6 link-local', () => {
      expect(isBlockedHost('fe80::1')).to.be.true;
    });

    it('should block IPv6 unique local (fc00 and fd00)', () => {
      expect(isBlockedHost('fc00::1')).to.be.true;
      expect(isBlockedHost('fd00::1234')).to.be.true;
    });

    it('should allow legitimate domains', () => {
      expect(isBlockedHost('example.com')).to.be.false;
      expect(isBlockedHost('github.com')).to.be.false;
      expect(isBlockedHost('google.com')).to.be.false;
    });
  });

  describe('validateURL', () => {
    it('should accept valid HTTPS URLs', () => {
      expect(validateURL('https://example.com').valid).to.be.true;
      expect(validateURL('https://github.com/user/repo').valid).to.be.true;
    });

    it('should reject SSRF attempts - localhost', () => {
      const result = validateURL('https://localhost/');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('blocked');
    });

    it('should reject SSRF attempts - AWS metadata', () => {
      const result = validateURL('https://169.254.169.254/latest/meta-data/');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('blocked');
    });

    it('should reject SSRF attempts - private IPs', () => {
      expect(validateURL('https://192.168.1.1/').valid).to.be.false;
      expect(validateURL('https://10.0.0.1/').valid).to.be.false;
    });

    it('should reject non-standard ports', () => {
      const result = validateURL('https://example.com:8080/');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('non-standard');
    });

    it('should include field name in error messages', () => {
      const result = validateURL('http://example.com', 'website');
      expect(result.error).to.include('website');
    });
  });

  describe('validateURLs', () => {
    it('should validate multiple URL fields', () => {
      const obj = {
        website: 'https://example.com',
        github: 'https://github.com/user',
      };
      const result = validateURLs(obj, ['website', 'github']);
      expect(result.valid).to.be.true;
      expect(result.errors).to.be.empty;
    });

    it('should skip undefined fields', () => {
      const obj = {
        website: 'https://example.com',
      };
      const result = validateURLs(obj, ['website', 'github']);
      expect(result.valid).to.be.true;
    });

    it('should collect all errors', () => {
      const obj = {
        website: 'http://example.com',
        github: 'https://localhost/',
      };
      const result = validateURLs(obj, ['website', 'github']);
      expect(result.valid).to.be.false;
      expect(result.errors).to.have.lengthOf(2);
    });
  });
});
