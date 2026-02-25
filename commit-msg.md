fixed:
- lobby shimmer builder duplication and non-async scroll handler that caused build errors
- logout now clears cached data via StorageService to prevent stale state

added:
- Hive-backed ChatCacheService initialization plus cache pruning utilities
- chat and lobby screens now load/save cached data and show shimmer placeholders during sync
