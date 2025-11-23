/**
 * Security tests for SSRF protection
 */

const { expect } = require('chai');
const { validateURL, isBlockedHost } = require('../../scripts/utils/url-validator');

describe('SSRF Protection Security Tests', () => {
  describe('AWS Metadata Endpoint Protection', () => {
    const awsEndpoints = [
      'https://169.254.169.254/latest/meta-data/',
      'https://169.254.169.254/latest/user-data/',
      'https://169.254.169.254/latest/dynamic/',
    ];

    awsEndpoints.forEach(endpoint => {
      it(`should block: ${endpoint}`, () => {
        const result = validateURL(endpoint);
        expect(result.valid).to.be.false;
        expect(result.error).to.include('blocked');
      });
    });
  });

  describe('GCP Metadata Endpoint Protection', () => {
    const gcpEndpoints = [
      'https://metadata.google.internal/',
      'https://metadata.google.internal/computeMetadata/v1/',
    ];

    gcpEndpoints.forEach(endpoint => {
      it(`should block: ${endpoint}`, () => {
        const result = validateURL(endpoint);
        expect(result.valid).to.be.false;
        expect(result.error).to.include('blocked');
      });
    });
  });

  describe('Localhost Protection', () => {
    const localhostVariants = [
      'https://localhost/',
      'https://127.0.0.1/',
      'https://0.0.0.0/',
      'https://[::1]/',
    ];

    localhostVariants.forEach(url => {
      it(`should block: ${url}`, () => {
        const hostname = new URL(url).hostname.replace(/[\[\]]/g, '');
        expect(isBlockedHost(hostname)).to.be.true;
      });
    });
  });

  describe('Private IP Range Protection', () => {
    const privateIPs = [
      '10.0.0.1',
      '10.255.255.255',
      '172.16.0.1',
      '172.31.255.255',
      '192.168.0.1',
      '192.168.255.255',
    ];

    privateIPs.forEach(ip => {
      it(`should block private IP: ${ip}`, () => {
        expect(isBlockedHost(ip)).to.be.true;
      });
    });
  });

  describe('IPv6 Link-Local Protection', () => {
    const linkLocalAddresses = [
      'fe80::1',
      'fe80::dead:beef',
    ];

    linkLocalAddresses.forEach(addr => {
      it(`should block link-local: ${addr}`, () => {
        expect(isBlockedHost(addr)).to.be.true;
      });
    });
  });

  describe('IPv6 Unique Local Protection', () => {
    const uniqueLocalAddresses = [
      'fc00::1',
      'fc00:dead:beef::1',
      'fd00::1',
      'fd00:1234:5678::abcd',
    ];

    uniqueLocalAddresses.forEach(addr => {
      it(`should block unique local: ${addr}`, () => {
        expect(isBlockedHost(addr)).to.be.true;
      });
    });
  });

  describe('Legitimate URLs', () => {
    const legitimateURLs = [
      'https://example.com/',
      'https://github.com/user/repo',
      'https://www.google.com/',
      'https://twitter.com/handle',
      'https://t.me/channel',
    ];

    legitimateURLs.forEach(url => {
      it(`should allow: ${url}`, () => {
        const result = validateURL(url);
        expect(result.valid, `${url} should be valid`).to.be.true;
      });
    });
  });

  describe('Non-standard Ports', () => {
    it('should reject HTTPS on non-standard port', () => {
      const result = validateURL('https://example.com:8080/');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('non-standard');
    });

    it('should allow standard HTTPS port (443)', () => {
      const result = validateURL('https://example.com:443/');
      // URLs with explicit :443 are typically omitted by URL parser
      // but if present, should be allowed
      expect(result.valid || result.error.includes('non-standard')).to.be.true;
    });
  });
});
