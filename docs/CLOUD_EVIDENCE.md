# Deployed Cloud Evidence

Observed on November 17, 2026 against Firebase project `mad-inclass16-gowtham-2026`. UIDs and document IDs are reduced to six-character suffixes. No password, token, or admin credential is included.

## Core observations

| Test | Observed result |
| --- | --- |
| T01 | Incorrect credentials returned `INVALID_LOGIN_CREDENTIALS`; the authorized account signed in successfully. |
| T02 | OpenTDB returned HTTP 200, response code 0, and five records. Encoded `The%20Doppler%20effect%20applies%20to%20light.` decoded to `The Doppler effect applies to light.` |
| T06 | Attempt suffix `c4a110` was created once, read from the server with a resolved timestamp, and a duplicate create returned `ALREADY_EXISTS`. |
| T07 | A new authentication session retrieved suffix `c4a110` from the server with the original score of 3. |
| T09 | A real commit existed before the injected verification failure; final server reconciliation read the same ID and no second document was needed. |
| T10 | User B was denied both read and write access to User A's path with `PERMISSION_DENIED`. |
| T11 | Update, score 6, and an extra field were all rejected with `PERMISSION_DENIED`; the original score remained 3. |

T03, T04, T05, T08, and T12 are additionally covered by automated validation, installed-app observations, and labeled development fault injection in the evidence report.

## Graduate observations

| Test | Observed result |
| --- | --- |
| G01 | Two clients attempted suffix `9be028` with scores 1 and 4. Exactly one create returned 200; the competing create returned `ALREADY_EXISTS`. The server winner was score 1, so the losing client reports collision. |
| G02 | Independent suffixes `360c51` and `7e4969` both created and both read from the server with their associated scores 2 and 5. |
| G03 | Automated tests proved that responses are accepted only when both initiating UID and round ID still match current state. A changed UID and a changed round ID were each rejected. |

The Firestore rules deployed for these observations are the repository's `firestore.rules`. They were not weakened for any test.
