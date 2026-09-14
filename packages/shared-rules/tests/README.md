# shared-rules tests

`fixtures/xp_curve.json` holds the expected numbers for the XP curve and is asserted by **both**
`tests/xp.test.ts` (Vitest) and `client/tests/test_rules_xp.gd` (GUT). That is how we prove the TS and the
generated GDScript agree (T-I.5 DoD). Regenerate it after changing `docs/balance/xp_curve.yaml`:

```
python3 scripts/gen_fixtures.py
```
