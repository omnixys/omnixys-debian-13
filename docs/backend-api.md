# Backend API

Each installer backend must implement these shell functions in installer/<name>/backend.sh:

- render
- validate
- build
- verify
- package

Contract:
- Exit code 0 for success.
- Non-zero for failure with actionable error output.
- Must respect DRY_RUN=true.
- Must write useful progress details to the shared build log.
