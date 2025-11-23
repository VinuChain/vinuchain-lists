# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

VinuChain Lists is a security-hardened token and smart contract registry for VinuChain blockchain (Chain ID: 207). This is a **data repository** with an enterprise-grade validation system, not a runtime application.

## Common Commands

### Validation
```bash
npm run validate              # Validate all tokens and contracts
LOG_FORMAT=json npm run validate  # JSON output for automation
DEBUG=1 npm run validate      # Debug mode with extra logging
```

### Testing
```bash
npm test                      # Run all 181 tests (~1 second)
npm run test:unit             # Unit tests only (103 tests)
npm run test:security         # Security tests only (72 tests)
npm run test:integration      # Integration tests only (6 tests)
npm run test:verbose          # Detailed test output
npm run test:watch            # Watch mode for TDD
npm run test:all              # Validation + all tests

# Run specific test file
npx mocha tests/unit/address-validator.test.js
```

### Security
```bash
npm audit                     # Check for dependency vulnerabilities (should always show 0)
```

## Architecture Overview

### Security-First Design

This codebase implements **defense-in-depth** with multiple validation layers. Every user input passes through:

1. **Schema validation** (JSON Schema) - Type and format checking
2. **Custom validation** (JavaScript code) - Security rules (EIP-55, path traversal, SSRF)
3. **Sanitization** (on output) - Terminal injection prevention

**Critical Security Principle:** Treat all file paths, JSON data, and URLs as potentially malicious. All inputs are validated before use.

### Modular Validation System

The validation system is split into focused modules:

**`scripts/validate.js`** - Orchestrator
- Loads schemas and initializes validators
- Coordinates validation flow: tokens → contracts → cross-references
- Uses logger for structured output
- **Never modify file operations directly here** - use utilities instead

**`scripts/utils/`** - Infrastructure
- `constants.js` - **Single source of truth** for all limits, patterns, blocked hosts
- `safe-json.js` - JSON parsing with prototype pollution protection (blocks `__proto__`, `constructor`, `prototype`)
- `address-validator.js` - EIP-55 checksum + path traversal protection
- `url-validator.js` - SSRF protection (50+ blocked hosts/IPs)
- `file-utils.js` - Safe file operations with path resolution checks
- `logger.js` - Structured logging (human + JSON formats)

**`scripts/validators/`** - Domain-specific validation
- `email-validator.js` - Disposable/reserved domain blocking
- `abi-validator.js` - ABI structure validation (prevents malicious parameter names)
- `solidity-validator.js` - Dangerous pattern detection (`selfdestruct`, `delegatecall`, `tx.origin`)

**Design Pattern:** All validators return `{valid: boolean, error?: string, warnings?: string[]}` for consistency.

### Data Flow

```
User Submission (PR/Issue)
    ↓
GitHub Actions Workflow (.github/workflows/validate.yml)
    ↓
validate.js orchestrator
    ├→ validateTokens()
    │   ├→ Schema validation (AJV)
    │   ├→ Address validation (EIP-55 + zero address check)
    │   ├→ URL validation (SSRF protection)
    │   └→ Email validation (domain blacklist)
    ├→ validateContracts()
    │   ├→ Schema validation
    │   ├→ Contract name validation (PascalCase + path safety)
    │   ├→ Solidity validation (pragma + dangerous patterns)
    │   └→ ABI validation (structure + parameter names)
    └→ validateCrossReferences()
        └→ Token project field references existing contract project
    ↓
Exit code 0 (success) or 1 (validation errors)
```

### Critical Security Patterns

**Path Traversal Protection:**
- Contract names: MUST be PascalCase (`/^[A-Z][a-zA-Z0-9]*$/`)
- Token directories: MUST be valid Ethereum addresses
- All paths resolved with `path.resolve()` and checked against base directory
- Never use `path.join()` directly - use `safePathJoin()` from `file-utils.js`

**SSRF Protection:**
- All URLs validated against blocked hosts (see `constants.js` BLOCKED_HOSTS/BLOCKED_IP_PATTERNS)
- Blocks: localhost, 127.0.0.1, private IPs (10.x, 172.16-31.x, 192.168.x), cloud metadata (169.254.169.254, metadata.google.internal), IPv6 link-local/ULA
- Never fetch URLs without validation

**Prototype Pollution Protection:**
- All JSON parsing uses `safeReadJSON()` or `safeParse()` from `safe-json.js`
- Reviver function blocks `__proto__`, `constructor`, `prototype` keys
- Never use `JSON.parse()` directly on user input

**Rate Limiting:**
- MAX_TOKENS: 10 per submission (configurable in constants.js)
- MAX_PROJECTS: 10 per repository
- MAX_CONTRACTS_PER_PROJECT: 50
- These prevent repository spam and CI/CD exhaustion

## Schema Modifications

When modifying schemas (`schemas/*.json`):

1. **URL patterns** must use `^https://[domain-pattern](/path)?$` format (no `.*` to prevent ReDoS)
2. **Always set maxLength** on strings to prevent DoS
3. **Contract names** must enforce PascalCase: `^[A-Z][a-zA-Z0-9]*$` (security requirement)
4. **Test changes** - Schema changes require corresponding test updates

## Adding New Validation

To add new validation logic:

1. **Choose module location:**
   - Generic utilities → `scripts/utils/`
   - Domain-specific validation → `scripts/validators/`

2. **Follow return pattern:** `{valid: boolean, error?: string, warnings?: string[]}`

3. **Add constants** to `scripts/utils/constants.js` (not magic numbers in code)

4. **Write tests FIRST:**
   - Unit test in `tests/unit/`
   - Security test if applicable in `tests/security/`
   - Must achieve 100% pass rate

5. **Document with JSDoc** including `@param`, `@returns`, `@throws`

## Test Organization

**Unit Tests** (`tests/unit/`) - Test individual functions in isolation
- One test file per module (e.g., `address-validator.test.js`)
- Mock file system operations when needed
- Fast execution (< 10ms per test)

**Integration Tests** (`tests/integration/`) - Test full validation flow
- Run actual validation on real repository data
- Test JSON output format
- Verify edge cases

**Security Tests** (`tests/security/`) - Test attack scenarios
- **Must verify actual attack prevention** (not just "should reject bad input")
- Test all items in BLOCKED_HOSTS and BLOCKED_IP_PATTERNS
- Verify prototype pollution doesn't actually pollute `{}.property`
- Test path traversal with actual path resolution

**Test Fixtures:** Create in `tests/fixtures/` for file-based tests (auto-cleanup in `after()` hooks)

## Important Conventions

### Error Messages
Use logger functions (not console.log):
```javascript
logger.error('Message');   // Increments error count, colored red
logger.warn('Message');    // Increments warning count, colored yellow
logger.info('Message');    // Informational, colored blue
logger.success('Message'); // Success, colored green
```

### File Operations
**Never use `fs` directly on user-controlled paths:**
```javascript
// ❌ WRONG - Vulnerable to path traversal
const data = JSON.parse(fs.readFileSync(userPath));

// ✅ CORRECT - Safe with validation
const data = safeReadJSON(userPath);  // Checks size, validates, blocks pollution
```

### Address Handling
**Always use EIP-55 validation:**
```javascript
// ❌ WRONG - Accepts invalid checksums
if (address.match(/^0x[a-fA-F0-9]{40}$/)) { ... }

// ✅ CORRECT - Validates checksum AND rejects zero address
const result = validateEIP55Checksum(address, 'TokenName');
if (!result.valid) {
  logger.error(result.error);
  return;
}
```

### URL Validation
**Always check for SSRF:**
```javascript
// ❌ WRONG - Vulnerable to SSRF
if (url.startsWith('https://')) { ... }

// ✅ CORRECT - Blocks internal IPs, metadata endpoints
const result = validateURL(url, 'website');
if (!result.valid) {
  logger.error(result.error);
  return;
}
```

## Token vs Contract Validation

### Token Validation (`validateTokens()`)
- Directory name MUST equal filename MUST equal address field (EIP-55)
- Optional `project` field creates cross-reference to contracts/{project-slug}
- URLs validated with SSRF protection
- Support field can be email (validated for disposable domains) - NOT a URL

### Contract Validation (`validateContracts()`)
- Each contract needs 3 files: info.json entry + .sol + _abi.json
- Contract names validated for security (PascalCase only, prevents path traversal)
- Duplicate contract names within project detected and rejected
- Solidity validated for: pragma, SPDX license (warning), contract declaration, dangerous patterns
- ABI validated for: structure, type validity, parameter names (blocks `__proto__` etc.)

### Cross-Reference Validation
- Tokens with `project` field must reference existing contract project
- Contract addresses that exist as tokens must have `project` field set correctly

## Common Tasks

### Adding a New Security Check

1. Add pattern/limit to `scripts/utils/constants.js`
2. Implement validator function in appropriate module
3. Add security test in `tests/security/` with attack scenarios
4. Update validation flow in `scripts/validate.js`
5. Verify all 181+ tests still pass

### Modifying Rate Limits

Edit `scripts/utils/constants.js`:
```javascript
MAX_TOKENS: 10,              // Tokens per submission
MAX_PROJECTS: 10,            // Projects per repository
MAX_CONTRACTS_PER_PROJECT: 50, // Contracts per project
```

**Important:** Rate limit changes should be accompanied by reasoning (DoS prevention vs. usability)

### Debugging Validation Failures

```bash
# Verbose validation output
npm run validate

# JSON output for parsing
LOG_FORMAT=json npm run validate | jq '.level == "error"'

# Debug specific module
DEBUG=1 npm run validate

# Run validation programmatically
node -e "const {validateTokens} = require('./scripts/validate'); validateTokens('./tokens')"
```

### Adding Blocked Hosts (SSRF Protection)

Edit `scripts/utils/constants.js`:
```javascript
BLOCKED_HOSTS: [
  'new-metadata-endpoint.cloud.provider',
  // ... existing hosts
],

BLOCKED_IP_PATTERNS: [
  /^new-range\./,  // Comment explaining the range
  // ... existing patterns
],
```

**Must add security test** in `tests/security/ssrf-protection.test.js` verifying the new host is blocked.

## logoURI vs logoURL

**Use `logoURI`** (not logoURL) - This follows the Uniswap Token Lists standard and ensures compatibility with wallets, DEXs, and aggregators. While technically a URL, the field name is `logoURI` for ecosystem compatibility.

## Security Audit

This repository achieved **Grade A+ (98/100)** after comprehensive security auditing. Key audit documents:
- `AUDIT_REPORT_UPDATED.md` - Post-fix verification and security certification
- `MISSION_COMPLETE.md` - Complete audit and remediation summary
- `TEST_RESULTS.md` - 181 tests, 100% passing

**When making changes:** If modifying validation logic or security features, review the audit report to ensure you don't reintroduce vulnerabilities.

## Git Workflow

**IMPORTANT: Commit after each logical change**

When working in this repository, commit frequently with clear messages:

```bash
# After fixing a bug
git add -A
git commit -m "Fix: Resolve issue with X validation"

# After adding a feature
git add -A
git commit -m "Add: New Y validation for Z"

# After adding tests
git add -A
git commit -m "Test: Add security tests for X protection"

# After updating documentation
git add -A
git commit -m "Docs: Update README with X information"
```

**Commit Guidelines:**
- **One logical change per commit** - If you fix a bug AND add a test, make 2 commits
- **Test before committing** - Always run `npm run test:all` before committing
- **Clear commit messages** - Use format: `Type: Brief description`
  - Types: `Fix`, `Add`, `Update`, `Refactor`, `Test`, `Docs`, `Security`
- **Commit frequently** - After each file change, feature addition, or bug fix
- **Include co-author** when using Claude Code:
  ```
  Type: Description

  Co-Authored-By: Claude <noreply@anthropic.com>
  ```

## Critical Files

**Never modify without thorough testing:**
- `scripts/utils/safe-json.js` - Prototype pollution protection
- `scripts/utils/address-validator.js` - Path traversal + EIP-55 validation
- `scripts/utils/url-validator.js` - SSRF protection
- `schemas/*.json` - Validation rules (changes affect all submissions)

**Always run full test suite after modifications:**
```bash
npm run test:all  # Validation + 181 tests
```

**After any modification to critical files:**
```bash
npm run test:all && git add -A && git commit -m "Security: Update X protection"
```

## VinuChain-Specific Details

- **Chain ID:** 207
- **Native Token:** VC
- **RPC:** https://rpc.vinuchain.org/
- **Explorer:** https://vinuexplorer.org/

**Address Format:** Standard Ethereum (EIP-55 checksummed), 0x + 40 hex characters

## Adding Contracts to Existing Projects

Users can add new contracts to existing projects by:
1. Updating `contracts/{project}/info.json` with new contract in the array
2. Adding `contracts/{project}/NewContract.sol`
3. Adding `contracts/{project}/NewContract_abi.json`

**Validation ensures:** No duplicate contract names within project, PascalCase enforcement, no duplicate addresses across registry.
