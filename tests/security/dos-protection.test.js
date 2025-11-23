/**
 * Security tests for DoS protection
 */

const { expect } = require('chai');
const fs = require('fs');
const path = require('path');
const { safeReadJSON } = require('../../scripts/utils/safe-json');

describe('DoS Protection Security Tests', () => {
  const testDir = path.join(__dirname, '../fixtures');

  before(() => {
    if (!fs.existsSync(testDir)) {
      fs.mkdirSync(testDir, { recursive: true });
    }
  });

  after(() => {
    // Cleanup test files
    if (fs.existsSync(testDir)) {
      const files = fs.readdirSync(testDir);
      files.forEach(file => {
        fs.unlinkSync(path.join(testDir, file));
      });
      fs.rmdirSync(testDir);
    }
  });

  describe('File Size Limits', () => {
    it('should reject JSON file larger than 100KB', function() {
      this.timeout(5000);

      const largePath = path.join(testDir, 'large.json');

      // Create file with 101KB of data
      const largeData = { data: 'x'.repeat(101 * 1024) };
      fs.writeFileSync(largePath, JSON.stringify(largeData));

      expect(() => safeReadJSON(largePath))
        .to.throw('File too large');
    });

    it('should accept JSON file under 100KB', () => {
      const validPath = path.join(testDir, 'valid.json');

      const validData = { test: 'data', value: 123 };
      fs.writeFileSync(validPath, JSON.stringify(validData));

      const result = safeReadJSON(validPath);
      expect(result).to.deep.equal(validData);
    });

    it('should respect custom size limits', () => {
      const filePath = path.join(testDir, 'medium.json');

      const data = { data: 'x'.repeat(1000) };
      fs.writeFileSync(filePath, JSON.stringify(data));

      // With 500 byte limit, should fail
      expect(() => safeReadJSON(filePath, 500))
        .to.throw('File too large');
    });
  });

  describe('Rate Limiting', () => {
    const { MAX_TOKENS, MAX_PROJECTS, MAX_CONTRACTS_PER_PROJECT } = require('../../scripts/utils/constants');

    it('should have token rate limit defined', () => {
      expect(MAX_TOKENS).to.be.a('number');
      expect(MAX_TOKENS).to.be.greaterThan(0);
    });

    it('should have project rate limit defined', () => {
      expect(MAX_PROJECTS).to.be.a('number');
      expect(MAX_PROJECTS).to.be.greaterThan(0);
    });

    it('should have contracts per project limit defined', () => {
      expect(MAX_CONTRACTS_PER_PROJECT).to.be.a('number');
      expect(MAX_CONTRACTS_PER_PROJECT).to.be.greaterThan(0);
    });
  });

  describe('Memory Exhaustion Protection', () => {
    it('should not allow deeply nested JSON to cause stack overflow', () => {
      const deeplyNested = { a: { b: { c: { d: { e: { f: { g: { h: { i: { j: 'value' } } } } } } } } } };
      const json = JSON.stringify(deeplyNested);

      // Should parse without error
      const { safeParse } = require('../../scripts/utils/safe-json');
      const result = safeParse(json);
      expect(result.a.b.c.d.e.f.g.h.i.j).to.equal('value');
    });

    it('should handle large arrays', () => {
      const largeArray = new Array(1000).fill('test');
      const json = JSON.stringify({ arr: largeArray });

      const { safeParse } = require('../../scripts/utils/safe-json');
      const result = safeParse(json);
      expect(result.arr).to.have.lengthOf(1000);
    });
  });
});
