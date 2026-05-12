# Expected Output

The demo should show:

- A fake agent reading a malicious README instruction.
- A blocked shell `.env` read attempt.
- A blocked synthetic network exfiltration attempt.
- A successful `aegis replay --session last --verify`.
- No generated fake secret value in terminal output or Aegis audit artifacts.

Exact session IDs and timestamps vary.
