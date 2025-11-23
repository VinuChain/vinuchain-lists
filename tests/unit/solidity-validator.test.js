/**
 * Unit tests for solidity-validator.js
 */

const { expect } = require('chai');
const {
  checkDangerousPatterns,
  validateSolidityFile,
} = require('../../scripts/validators/solidity-validator');

describe('Solidity Validator', () => {
  describe('checkDangerousPatterns', () => {
    it('should detect selfdestruct', () => {
      const code = 'function destroy() { selfdestruct(owner); }';
      const warnings = checkDangerousPatterns(code);
      expect(warnings).to.have.lengthOf.at.least(1);
      expect(warnings[0]).to.include('selfdestruct');
    });

    it('should detect delegatecall', () => {
      const code = 'address(target).delegatecall(data);';
      const warnings = checkDangerousPatterns(code);
      expect(warnings.some(w => w.includes('delegatecall'))).to.be.true;
    });

    it('should detect tx.origin', () => {
      const code = 'require(tx.origin == owner);';
      const warnings = checkDangerousPatterns(code);
      expect(warnings.some(w => w.includes('tx.origin'))).to.be.true;
    });

    it('should return empty array for safe code', () => {
      const code = 'function transfer(address to, uint amount) public { }';
      const warnings = checkDangerousPatterns(code);
      expect(warnings).to.be.empty;
    });
  });

  describe('validateSolidityFile', () => {
    it('should accept valid Solidity file', () => {
      const code = `
        // SPDX-License-Identifier: MIT
        pragma solidity ^0.8.0;

        contract TestContract {
          uint256 public value;
        }
      `;
      const result = validateSolidityFile(code, 'TestContract');
      expect(result.valid).to.be.true;
    });

    it('should reject empty file', () => {
      const result = validateSolidityFile('', 'TestContract');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('empty');
    });

    it('should reject file without pragma', () => {
      const code = `
        contract TestContract {
          uint256 public value;
        }
      `;
      const result = validateSolidityFile(code, 'TestContract');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('pragma');
    });

    it('should reject file without matching contract declaration', () => {
      const code = `
        // SPDX-License-Identifier: MIT
        pragma solidity ^0.8.0;

        contract WrongName {
          uint256 public value;
        }
      `;
      const result = validateSolidityFile(code, 'TestContract');
      expect(result.valid).to.be.false;
      expect(result.error).to.include('No declaration found');
    });

    it('should warn about missing SPDX license', () => {
      const code = `
        pragma solidity ^0.8.0;

        contract TestContract {
          uint256 public value;
        }
      `;
      const result = validateSolidityFile(code, 'TestContract');
      expect(result.valid).to.be.true;
      expect(result.warnings).to.be.an('array').that.is.not.empty;
      const hasSPDXWarning = result.warnings.some(w => w.includes('SPDX'));
      expect(hasSPDXWarning).to.be.true;
    });

    it('should accept interface declarations', () => {
      const code = `
        // SPDX-License-Identifier: MIT
        pragma solidity ^0.8.0;

        interface TestContract {
          function test() external;
        }
      `;
      const result = validateSolidityFile(code, 'TestContract');
      expect(result.valid).to.be.true;
    });

    it('should accept library declarations', () => {
      const code = `
        // SPDX-License-Identifier: MIT
        pragma solidity ^0.8.0;

        library TestContract {
          function test() internal {}
        }
      `;
      const result = validateSolidityFile(code, 'TestContract');
      expect(result.valid).to.be.true;
    });

    it('should warn about dangerous patterns', () => {
      const code = `
        // SPDX-License-Identifier: MIT
        pragma solidity ^0.8.0;

        contract TestContract {
          function destroy() public {
            selfdestruct(payable(msg.sender));
          }
        }
      `;
      const result = validateSolidityFile(code, 'TestContract');
      expect(result.valid).to.be.true;
      expect(result.warnings).to.exist;
      expect(result.warnings.some(w => w.includes('selfdestruct'))).to.be.true;
    });
  });
});
