/**
 * Unit tests for safe-json.js
 */

const { expect } = require('chai');
const fs = require('fs');
const path = require('path');
const { safeParse, safeReadJSON, sanitizeForTerminal } = require('../../scripts/utils/safe-json');

describe('Safe JSON Parser', () => {
  describe('safeParse', () => {
    it('should parse valid JSON', () => {
      const result = safeParse('{"name": "test", "value": 123}');
      expect(result).to.deep.equal({ name: 'test', value: 123 });
    });

    it('should block __proto__ pollution', () => {
      const result = safeParse('{"__proto__": {"polluted": true}, "name": "test"}');
      expect(result.name).to.equal('test');
      expect({}.polluted).to.be.undefined;
    });

    it('should block constructor pollution', () => {
      const result = safeParse('{"constructor": {"prototype": {"polluted": true}}}');
      expect({}.polluted).to.be.undefined;
    });

    it('should block prototype pollution', () => {
      const result = safeParse('{"prototype": {"polluted": true}}');
      expect({}.polluted).to.be.undefined;
    });

    it('should throw on invalid JSON', () => {
      expect(() => safeParse('invalid json')).to.throw(SyntaxError);
    });

    it('should handle nested objects', () => {
      const json = '{"outer": {"inner": {"value": 42}}}';
      const result = safeParse(json);
      expect(result.outer.inner.value).to.equal(42);
    });

    it('should handle arrays', () => {
      const result = safeParse('[1, 2, 3]');
      expect(result).to.deep.equal([1, 2, 3]);
    });
  });

  describe('safeReadJSON', () => {
    const testDir = path.join(__dirname, '../fixtures');
    const validFile = path.join(testDir, 'valid.json');
    const largeFile = path.join(testDir, 'large.json');

    before(() => {
      // Create test directory and files
      if (!fs.existsSync(testDir)) {
        fs.mkdirSync(testDir, { recursive: true });
      }

      // Valid JSON file
      fs.writeFileSync(validFile, JSON.stringify({ test: 'data' }));

      // Large file (over 100KB)
      const largeData = { data: 'x'.repeat(110 * 1024) };
      fs.writeFileSync(largeFile, JSON.stringify(largeData));
    });

    after(() => {
      // Cleanup
      if (fs.existsSync(validFile)) fs.unlinkSync(validFile);
      if (fs.existsSync(largeFile)) fs.unlinkSync(largeFile);
      if (fs.existsSync(testDir)) fs.rmdirSync(testDir);
    });

    it('should read and parse valid JSON file', () => {
      const result = safeReadJSON(validFile);
      expect(result).to.deep.equal({ test: 'data' });
    });

    it('should throw on missing file', () => {
      expect(() => safeReadJSON(path.join(testDir, 'nonexistent.json')))
        .to.throw('File not found');
    });

    it('should throw on file too large', () => {
      expect(() => safeReadJSON(largeFile))
        .to.throw('File too large');
    });

    it('should respect custom max size', () => {
      expect(() => safeReadJSON(validFile, 10))
        .to.throw('File too large');
    });
  });

  describe('sanitizeForTerminal', () => {
    it('should remove control characters', () => {
      const result = sanitizeForTerminal('test\x00\x01\x1F');
      expect(result).to.equal('test');
    });

    it('should remove ANSI escape codes', () => {
      const result = sanitizeForTerminal('\x1b[31mRed Text\x1b[0m');
      expect(result).to.equal('Red Text');
    });

    it('should handle non-string input', () => {
      expect(sanitizeForTerminal(123)).to.equal('123');
      expect(sanitizeForTerminal(null)).to.equal('null');
    });

    it('should preserve normal text', () => {
      const text = 'Normal text with spaces and punctuation!';
      expect(sanitizeForTerminal(text)).to.equal(text);
    });
  });
});
