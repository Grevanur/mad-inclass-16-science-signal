# Application State Machine

```text
signed out
   │ valid authentication
   ▼
loading questions ── invalid response ──► request error ── bounded retry ─┐
   │ five validated questions                                            │
   ▼                                                                     │
playing ── one selection per question ──► ready to submit ◄───────────────┘
   │ freeze uid round id and score
   ▼
submitting ── unknown acknowledgement ──► save unknown
   │ acknowledged                                  │ reconcile same id
   ▼                                               ▼
verifying ── denied unavailable exhausted ──► verification unavailable
   │ exact server document                         │ bounded server retry
   ▼                                               │
cloud verified ◄───────────────────────────────────┘

Any mismatched existing payload enters collision. Replay and sign-out remain
disabled while submission or verification is unresolved. A response updates
the UI only if both its initiating UID and round ID still match current state.
```
