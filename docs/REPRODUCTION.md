# Failure and Graduate Reproduction

Use only authorized test accounts and the deployed project. Do not change `firestore.rules` during any test.

## T08 Offline reconciliation

1. Complete a round while online but do not submit.
2. Disable network connectivity and select **Submit immutable attempt**.
3. Confirm that no cloud success is shown. A transaction that cannot complete reports an unavailable or unknown outcome.
4. Restore connectivity and select **Reconcile original ID**.
5. Confirm the original ID is read from the server or remains explicitly not found. Do not replay or create a second ID while unresolved.

## T09 Acknowledged write and denied verification

1. Run a debug build and expand **Development evidence lab**.
2. Select `permissionDeniedOnce` and submit a completed round online.
3. The real transaction commits, then the development hook rejects only the first verification response.
4. Confirm the amber state says `Write acknowledged; verification unavailable (permission-denied)` and keeps replay and sign-out disabled.
5. Select **Reconcile original ID**. The same server document must become `Cloud verified` with no second write.

## T10 and T11 Deployed rules

Sign in as User B and attempt a server read and create under User A's UID. Both return `PERMISSION_DENIED`. As User A, attempt an update, a score of 6, and an extra field. All are denied and the original record remains unchanged. These checks were executed against the deployed Standard database, not only an emulator.

## T12 Bounded service faults

In a debug build, repeat a completed round with `unavailable` and `resourceExhausted`. Each produces a distinct visible code, never shows cloud success, preserves the original ID, and offers only the user-triggered reconciliation action. The hook throws before the server verification response; it does not consume real quota or alter deployed rules.

## G01 Same ID with different scores

Use two clients authenticated as the same user. Submit the same round ID with different fixed payloads at the same time. Exactly one create wins. The other client reads the existing fields, detects a fixed-field mismatch, and reports collision rather than overwriting the winner.

## G02 Independent round isolation

Submit two different round IDs concurrently from two clients. Both writes and server reads must succeed. Each callback retains its initiating UID and round ID, so the score 2 response cannot be attached to the score 5 round or vice versa.

## G03 Stale authentication response

Start a delayed verification for User A, then change authentication to User B before it returns. `OperationIdentity.isCurrent` requires both the initiating UID and round ID to match current state; the stale response is discarded. The automated contract test also covers a stale cross-round response for the same UID.
