# Architecture Context

## Production Constraints
- Rolling deploy: old and new binaries run side by side for several minutes on every release.
- Migrations run before the new binary starts. Every migration must have a working down path.
