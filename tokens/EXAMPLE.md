# Example Token Entry

This is an example of how to structure a token entry in the VinuChain Tokens List.

## Directory Structure

Each token must have its own directory named by its EIP-55 checksummed contract address:

```
tokens/
└── 0x00c1E515EA9579856304198EFb15f525A0bb50f6/
    └── 0x00c1E515EA9579856304198EFb15f525A0bb50f6.json
```

## File Content

The JSON file must contain the following structure:

### Minimal Example (Required Fields Only)

```json
{
  "symbol": "VINU",
  "name": "Vita Inu",
  "address": "0x00c1E515EA9579856304198EFb15f525A0bb50f6",
  "decimals": 18
}
```

### Complete Example (All Fields)

```json
{
  "symbol": "VINU",
  "name": "Vita Inu",
  "address": "0x00c1E515EA9579856304198EFb15f525A0bb50f6",
  "decimals": 18,
  "description": "Bridged VINU on VinuChain, bringing the vibrant community and innovative features of Vita Inu to the VinuChain ecosystem.",
  "project": "vinuswap",
  "logoURI": "https://vinuexplorer.org/icons/vitainu.svg",
  "website": "https://vitainu.org",
  "support": "hello@vitainu.org",
  "github": "https://github.com/vita-inu",
  "twitter": "https://twitter.com/vitainucoin",
  "telegram": "https://t.me/vitainu",
  "discord": "https://discord.gg/vinu",
  "coingecko": "https://www.coingecko.com/en/coins/vita-inu",
  "coinmarketcap": "https://coinmarketcap.com/currencies/vita-inu/",
  "medium": "https://medium.com/vitainu",
  "linkedin": "https://linkedin.com/company/vinufoundation",
  "instagram": "https://instagram.com/vitainucoin",
  "facebook": "https://facebook.com/vitainucoin",
  "reddit": "https://reddit.com/r/vitainu",
  "youtube": "https://youtube.com/c/vitainucoin",
  "redFlags": [
    {
      "severity": "low",
      "description": "Contract not verified on explorer",
      "evidence": "https://vinuexplorer.org/address/0x00c1E515EA9579856304198EFb15f525A0bb50f6",
      "reportedDate": "2024-01-15"
    }
  ]
}
```

## Field Descriptions

### Required Fields

- **symbol**: Token ticker symbol (uppercase, 1-20 characters, alphanumeric only)
- **name**: Full token name (1-100 characters)
- **address**: EIP-55 checksummed contract address (must match directory and filename)
- **decimals**: Number of decimal places (integer, 0-18)

### Optional Fields

- **description**: Brief description of the token and its purpose
  - Length: 10-500 characters
  - Example: "Bridged VINU on VinuChain, bringing the vibrant community and innovative features of Vita Inu to the VinuChain ecosystem."

- **project**: Reference to associated smart contract project in `contracts/` directory
  - Format: lowercase slug (e.g., "vinuswap")
  - Must match an existing project in the contracts directory

- **logoURI**: HTTPS URL to token logo image
  - Recommended: 200x200px PNG with transparent background
  - Maximum: 512x512px
  - File size: < 100KB recommended

- **website**: Official project website (HTTPS URL)

- **support**: Support/contact email address
  - Must be a valid email format
  - Disposable email domains are blocked

- **github**: GitHub repository or organization URL
  - Format: `https://github.com/username/repo` or `https://github.com/org`

- **twitter**: Twitter/X profile URL
  - Format: `https://twitter.com/handle` or `https://x.com/handle`

- **telegram**: Telegram group or channel URL
  - Format: `https://t.me/groupname`

- **discord**: Discord server invite URL
  - Format: `https://discord.gg/invite` or `https://discord.com/invite/code`

- **coingecko**: CoinGecko listing URL
  - Format: `https://www.coingecko.com/en/coins/token-name`

- **coinmarketcap**: CoinMarketCap listing URL
  - Format: `https://coinmarketcap.com/currencies/token-name/`

- **medium**: Medium blog or publication URL
  - Format: `https://medium.com/publication-name`

- **linkedin**: LinkedIn company or profile URL
  - Format: `https://linkedin.com/company/name` or `https://linkedin.com/in/profile`

- **instagram**: Instagram profile URL
  - Format: `https://instagram.com/username`

- **facebook**: Facebook page URL
  - Format: `https://facebook.com/pagename`

- **reddit**: Reddit community URL
  - Format: `https://reddit.com/r/subredditname`

- **youtube**: YouTube channel URL
  - Format: `https://youtube.com/c/channelname` or `https://youtube.com/@handle`

- **redFlags**: Array of security warnings (use sparingly, with evidence)
  - Each flag must include: severity, description, and optionally evidence and reportedDate
  - Severity levels: critical, high, medium, low, info
  - Example structure shown in complete example above

## Validation

Before submitting, validate your token file:

```bash
npm install
npm run validate
```

The validation script will check:
- ✅ Directory name matches address
- ✅ Filename matches address
- ✅ Address in JSON matches directory/filename
- ✅ Address is EIP-55 checksummed
- ✅ All required fields are present
- ✅ All fields match schema constraints
- ✅ No duplicate addresses exist
- ⚠️  Duplicate symbols (warning only)

## Common Mistakes to Avoid

1. **Wrong directory structure**
   ```
   ❌ tokens/vinu/0xAddress.json
   ✅ tokens/0xAddress/0xAddress.json
   ```

2. **Filename doesn't match directory**
   ```
   ❌ tokens/0xAddress/token.json
   ✅ tokens/0xAddress/0xAddress.json
   ```

3. **Address not checksummed**
   ```
   ❌ "address": "0x00c1e515ea9579856304198efb15f525a0bb50f6"
   ✅ "address": "0x00c1E515EA9579856304198EFb15f525A0bb50f6"
   ```

4. **Address mismatch**
   ```json
   // Directory: tokens/0x00c1E515EA9579856304198EFb15f525A0bb50f6/
   {
     "address": "0xDifferentAddress"  // ❌ Must match directory!
   }
   ```

## Getting Help

- Read the [CONTRIBUTING.md](../CONTRIBUTING.md) guide
- Check existing tokens for examples
- Run validation and read error messages
- Open an issue if you need assistance

---

For more information, see the [README.md](../README.md) and [QUICKSTART.md](../QUICKSTART.md).
