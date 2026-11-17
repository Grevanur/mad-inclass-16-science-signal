# Science Signal Class B

Science Signal is the graduate implementation of Georgia State University MAD In-Class Activity 16, Class B. It loads exactly five medium Science and Nature true-or-false questions, reviews every answer, creates an immutable attempt under the authenticated Firebase user, and confirms the exact document with a server-only read.

## Verified environment

- Flutter 3.47.2 and Dart 3.13.2
- Android package `edu.gsu.gowtham.inclass_16`
- Firebase project `mad-inclass16-gowtham-2026`
- Cloud Firestore Standard edition, Native mode, `nam5`
- Email and Password authentication
- OpenTDB category 17 endpoint with URL-3986 encoding

## Cloud contract

Attempts use `users/{authenticatedUid}/attempts/{roundId}`. The document ID is the round ID and is never stored as another field. The six stored fields are:

| Field | Required value |
| --- | --- |
| `schemaVersion` | Integer `1` |
| `variant` | String `B` |
| `categoryId` | Integer `17` |
| `questionCount` | Integer `5` |
| `correctCount` | Integer `0` through `5` |
| `submittedAt` | Firestore server timestamp |

The client transaction reads first, creates only when absent, reuses an identical payload, and reports a collision instead of overwriting a different payload. Verification uses `Source.server`, requires an exact schema and resolved `Timestamp`, and rejects snapshots with pending writes.

## Run and verify

1. Install Flutter 3.47 or a compatible stable release and Android tooling.
2. Run `flutter pub get`.
3. Use an instructor-authorized Email and Password test account. Credentials are deliberately not stored in this repository.
4. Run `flutter run` for development evidence controls or install the supplied release APK.
5. Complete all five questions, review the selections, and submit.
6. Confirm that the app reports `Cloud verified`, displays the full round ID and resolved UTC server timestamp, and that the matching document exists in Firestore.
7. To reproduce restart retrieval, copy the round ID, force-stop and reopen the app while online, sign in as the same user, expand **Retrieve an existing round**, enter the ID, and select **Read from server**.

## Graduate two-client procedure

For G01, start two debug clients signed in as the same authorized user. Give both clients the same round ID but different scores and submit concurrently. The deployed create-once transaction permits one payload; the other client reads the winner and reports a collision. For G02, repeat with distinct round IDs; both records must verify and each response must remain attached to its initiating ID. For G03, begin a delayed verification, change authentication externally, and confirm that `OperationIdentity` prevents the old UID and round response from updating the new user interface.

The reproducible deployed-cloud results and redacted round suffixes are in [docs/CLOUD_EVIDENCE.md](docs/CLOUD_EVIDENCE.md). The evidence report contains the full 15-record matrix and analysis.

## Tests and release

```text
flutter analyze
flutter test
flutter build apk --release
```

The release output is `build/app/outputs/flutter-apk/app-release.apk`. It was installed and launched on an Android 37.1 Google APIs Play Store ARM64 emulator. Development-only fault injection is compiled out of release behavior through `kDebugMode`.

## Security

- Firestore rules are owner-only, schema-exact, create-only, and deny updates and deletes.
- Passwords, ID tokens, refresh tokens, service accounts, admin SDK credentials, and private keys are not stored or logged.
- `google-services.json` and `firebase_options.dart` contain Firebase client identifiers. They are intentionally distributable client configuration, not privileged server credentials; authorization remains enforced by Authentication and Firestore rules.
- Invalid schema and ownership tests use deployed rules. Fault injection never changes production rules or deliberately consumes quota.
- The final repository and Git history are scanned before release.

## AI assistance disclosure

OpenAI Codex assisted with implementation, tests, evidence organization, documentation, and verification on November 17, 2026. All cloud claims in the evidence report are tied to observed automated or deployed-cloud results; unobserved behavior is not presented as a pass.
