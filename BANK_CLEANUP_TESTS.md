# Assisted Bank Cleanup v1 — In-Game Test Cases

Environment: Burning Crusade Classic Anniversary 2.5.5
Command: `/bankx`

This checklist validates the first production implementation. It does not establish production readiness until the in-game cases pass.

## Preparation

1. Use inexpensive, non-usable stackable materials.
2. Record the item IDs and exact quantities in bags and bank before transfer tests.
3. Run:

   ```text
   /reload
   ```

4. Confirm `/gearx`, `/itemx`, and `/bagsx` still open their normal exports without errors or format changes.
5. Open `/bankx` and confirm the Assisted Bank Cleanup frame appears.

Record any Lua error, blocked-action warning, red Blizzard error, taint popup, stuck cursor item, or unexpected inventory movement.

---

## Parsing tests

### P1 — Valid one-line plan

```text
GEARX_BANK_PLAN_V1
DEPOSIT|2996|1
```

Expected:

- Import succeeds.
- One `Current` move appears.
- Item ID, requested quantity, item name or uncached-name fallback, and bag availability appear.
- Import causes no inventory movement.

Result:

- Pass/fail: Pass
- Observed status: Test gave 1 current move exactly as expected
- Notes:

### P2 — Valid mixed plan

Replace IDs or quantities with items actually available for testing.

```text
GEARX_BANK_PLAN_V1
DEPOSIT|2996|1
WITHDRAW|2589|1
```

Expected:

- Both moves appear.
- Move 1 is `Current`.
- Move 2 is `Pending`.
- Source availability appears for both while the bank is open.
- No item moves during import.

Result:

- Pass/fail: Pass
- Observed status:
- Notes:

### P3 — Invalid header

```text
GEARX_BANK_PLAN_V2
DEPOSIT|2996|1
```

Expected: exact-header error and no active plan.

Result:

- Pass/fail: Pass
- Error text: Plan Import Error

Line 1 must exactly match GEARX_BANK_PLAN_V1.

Click this area, press Ctrl+A, then Ctrl+C to copy the error.

### P4 — Unsupported verb

Test each separately:

```text
GEARX_BANK_PLAN_V1
SELL|2996|1
```

```text
GEARX_BANK_PLAN_V1
MOVE|2996|1
```

Expected: hard unsupported-verb error; no lines are silently ignored.

Result:

- Pass/fail: Pass
- Error text:Plan Import Error

Unsupported verb on line 2: MOVE

Click this area, press Ctrl+A, then Ctrl+C to copy the error.

### P5 — Malformed item ID

```text
GEARX_BANK_PLAN_V1
DEPOSIT|linen|1
```

Expected: item ID must be a positive integer.

Result:

- Pass/fail: Pass
- Error text: Plan Import Error

Item ID must be a positive integer on line 2.

Click this area, press Ctrl+A, then Ctrl+C to copy the error.

### P6 — Zero quantity

```text
GEARX_BANK_PLAN_V1
DEPOSIT|2996|0
```

Expected: quantity must be a positive integer.

Result:

- Pass/fail: Pass
- Error text:Plan Import Error

Quantity must be a positive integer on line 2.

Click this area, press Ctrl+A, then Ctrl+C to copy the error.

### P7 — Negative quantity

```text
GEARX_BANK_PLAN_V1
DEPOSIT|2996|-1
```

Expected: quantity must be a positive integer.

Result:

- Pass/fail: pass
- Error text: Plan Import Error

Quantity must be a positive integer on line 2.

Click this area, press Ctrl+A, then Ctrl+C to copy the error.

### P8 — Malformed lines

Test each separately:

```text
GEARX_BANK_PLAN_V1
DEPOSIT|2996
```

```text
GEARX_BANK_PLAN_V1
DEPOSIT|2996|1|EXTRA
```

```text
GEARX_BANK_PLAN_V1
Deposit 1 item 2996
```

Expected: each plan fails completely rather than being guessed, partially imported, or silently ignored.

Result:

- Pass/fail: pass
- Error text for each fixture:Plan Import Error

Malformed plan line 2. Stored text: "Deposit 1 item 2996"

Click this area, press Ctrl+A, then Ctrl+C to copy the error.

---

## Safety and live-revalidation tests

### S1 — Import while bank is closed

```text
GEARX_BANK_PLAN_V1
DEPOSIT|2996|1
```

Expected:

- Import and preview are allowed.
- Import causes no movement.
- Status says the normal bank must be opened.
- Execute is disabled.
- Opening the bank enables execution but does not automatically move anything.

Result:

- Pass/fail: pass
- Observed status:
- Unexpected movement:

### S2 — Close bank before execution

1. Import a valid plan while the bank is open.
2. Close the bank before clicking Execute.

Expected:

- Execute becomes disabled.
- No transfer occurs.
- Status says the bank must be reopened.

Result:

- Pass/fail: pass
- Observed status:

### S3 — Non-empty cursor

1. Open the bank and import a valid plan.
2. Pick up a harmless item with the normal Blizzard UI.
3. Click `Execute Next Move`.
4. Return the cursor item manually.

Expected:

- Execution aborts.
- GearExport does not clear or alter the cursor.
- No planned quantity moves.
- Current plan move remains unexecuted.

Result:

- Pass/fail: pass
- Observed status:
- Cursor behavior:
- Quantity changes:

### S4 — Source removed after import

1. Import a valid deposit plan.
2. Manually move the source item into the bank.
3. Click Execute.

Expected:

- No substitute is selected.
- No additional quantity moves.
- Current move becomes `Failed`.
- Progression stops and current availability is reported.

Result:

- Pass/fail: pass
- Observed status:
- Final move state:Bank Cleanup Plan

1. [Failed] DEPOSIT
    1 Bolt of Linen Cloth
    Item ID 2996; 0 available in bags
    Cannot execute DEPOSIT 1 Bolt of Linen Cloth. Requested 1; currently available: 0. Available in bags: 0.

Bank Cleanup Plan Complete
Completed: 0   Skipped: 0   Failed: 1

### S5 — Source quantity reduced after import

1. Import a plan requesting 5.
2. Manually reduce the source location to 4.
3. Click Execute.

Expected:

- GearExport does not transfer 4.
- Move becomes `Failed`.
- Requested and currently available quantities are reported.

Result:

- Pass/fail: pass
- Requested/available message:Bank Cleanup Plan

1. [Failed] DEPOSIT
    5 Bolt of Linen Cloth
    Item ID 2996; 4 available in bags
    Cannot execute DEPOSIT 5 Bolt of Linen Cloth. Requested 5; currently available: 4. Available in bags: 4.

Bank Cleanup Plan Complete
Completed: 0   Skipped: 0   Failed: 1
- Quantity moved:0

### S6 — Quantity spans multiple source stacks

Arrange two source stacks, such as 3 and 2, with no single stack containing the requested 5.

```text
GEARX_BANK_PLAN_V1
DEPOSIT|<itemID>|5
```

Expected:

```text
Requested quantity spans multiple stacks. Split the plan into multiple moves.
```

No transfer occurs.

Result:

- Pass/fail: pass
- Error text: Bank Cleanup Plan

1. [Failed] DEPOSIT
    5 Bolt of Linen Cloth
    Item ID 2996; 5 available in bags
    Cannot execute DEPOSIT 5 Bolt of Linen Cloth. Requested quantity spans multiple stacks. Split the plan into multiple moves. Available in bags: 5.

Bank Cleanup Plan Complete
Completed: 0   Skipped: 0   Failed: 1
- Quantity moved:

### S7 — Insufficient destination space

Use a character/storage location where every compatible destination slot is occupied. A partial transfer is the clearest test because it requires an explicitly empty slot.

Expected:

- Move fails before splitting.
- Nothing is placed on the cursor.
- No inventory movement occurs.

Do not create a risky inventory arrangement merely to force this test.

Result:

- Pass/fail/not practical: pass
- Observed status:Bank Cleanup Plan

1. [Failed] DEPOSIT
    5 Bolt of Linen Cloth
    Item ID 2996; 5 available in bags
    No safe destination capacity is available for this full-stack move.

Bank Cleanup Plan Complete
Completed: 0   Skipped: 0   Failed: 1
- Cursor behavior:

### S8 — Locked source

If practical, click Execute while the intended source stack is visibly locked by another normal inventory operation.

Expected:

- No transfer occurs.
- A locked-source error appears.
- An unrelated or insufficient stack is not substituted.

Result:

- Pass/fail/not practical: not practical
- Observed status:

---

## Transfer tests

For every transfer, record bags and bank totals before and after. Wait until the frame reports verification success or failure.

### T1 — Full stack: bags to bank

Use a plan quantity exactly equal to one bag source stack:

```text
GEARX_BANK_PLAN_V1
DEPOSIT|<itemID>|<fullStackQuantity>
```

Expected:

- One Execute click initiates one transfer.
- Execute is disabled while waiting.
- Cursor remains empty.
- Bags decrease and bank increases by exactly the request.
- Move becomes `Complete` only after verification.

Result:

- Pass/fail:
- Plan line: 2
- Before bags/bank: 15/58
- After bags/bank:5/68/
- Final status and move message:Bank Cleanup Plan

1. [Complete] DEPOSIT
    10 Bolt of Linen Cloth
    Item ID 2996; 5 available in bags
    Verified exactly: bags 5, bank 68.

Bank Cleanup Plan Complete
Completed: 1   Skipped: 0   Failed: 0
- Cursor empty:
- Errors:

### T2 — Full stack: bank to bags

```text
GEARX_BANK_PLAN_V1
WITHDRAW|<itemID>|<fullStackQuantity>
```

Expected:

- One Execute click initiates one transfer.
- Bank decreases and bags increase by exactly the request.
- Move becomes `Complete` after asynchronous verification.

Result:

- Pass/fail:PASS
- Plan line:2
- Before bags/bank: 5/63
- After bags/bank: 15/58
- Final status and move message: Bank Cleanup Plan

1. [Complete] WITHDRAW
    10 Bolt of Linen Cloth
    Item ID 2996; 58 available in bank
    Verified exactly: bags 15, bank 58.

Bank Cleanup Plan Complete
Completed: 1   Skipped: 0   Failed: 0
- Cursor empty:
- Errors:

### T3 — Partial stack: bags to bank

Use a quantity smaller than one source stack:

```text
GEARX_BANK_PLAN_V1
DEPOSIT|<itemID>|<partialQuantity>
```

Expected:

- Split and placement complete during one Execute click.
- Cursor ends empty.
- Exactly the requested quantity moves.
- Move becomes `Complete` after verification.

Result:

- Pass/fail: PASS
- Plan line:
- Source stack before/after:
- Before bags/bank:
- After bags/bank:
- Final status and move message:
- Cursor empty:
- Errors:

### T4 — Partial stack: bank to bags

```text
GEARX_BANK_PLAN_V1
WITHDRAW|<itemID>|<partialQuantity>
```

Expected:

- Split and placement complete during one Execute click.
- Cursor ends empty.
- Exactly the requested quantity moves.
- Move becomes `Complete` after verification.

Result:

- Pass/fail: PASS
- Plan line:
- Source stack before/after:
- Before bags/bank:
- After bags/bank:
- Final status and move message:
- Cursor empty:
- Errors:

---

## Workflow tests

### W1 — Two moves require two clicks

Import two valid moves.

1. Click Execute once.
2. Wait for move 1 to become `Complete`.
3. Do not click anything for at least five seconds.
4. Confirm move 2 remains `Current` and no second transfer occurs.
5. Click Execute again.

Expected: exactly two explicit Execute clicks and no automatic second transfer.

Result:

- Pass/fail: PASS
- Plan:
- State after first verification:
- Inventory after five-second wait:
- State after second click:

### W2 — Skip performs no movement

1. Import at least two valid moves.
2. Record quantities.
3. Click `Skip Move` on the first.

Expected:

- First move becomes `Skipped`.
- Second becomes `Current`.
- Inventory quantities do not change.
- No transfer starts.

Result:

- Pass/fail: PASS
- Before/after quantities:
- Displayed states:

### W3 — Cancel performs no movement

1. Import a plan.
2. Record quantities.
3. Click `Cancel Plan` before execution.

Expected:

- Active plan is discarded.
- Preview says no plan is imported.
- Inventory is unchanged.

Result:

- Pass/fail: PASS
- Before/after quantities:
- Observed status:

### W4 — Completion summary

Complete and/or skip every move in a plan.

Expected:

```text
Bank Cleanup Plan Complete
```

The Complete, Skipped, and Failed counts must be correct.

Result:

- Pass/fail: PASS
- Summary text: Bank Cleanup Plan

1. [Complete] DEPOSIT
    5 Bolt of Linen Cloth
    Item ID 2996; 20 available in bags
    Verified exactly: bags 15, bank 58.

2. [Complete] WITHDRAW
    5 Bolt of Linen Cloth
    Item ID 2996; 53 available in bank
    Verified exactly: bags 20, bank 53.

Bank Cleanup Plan Complete
Completed: 2   Skipped: 0   Failed: 0

---

## Verification tests

### V1 — Exact movement and asynchronous settling

Use any successful transfer test.

Expected:

- Move is not marked complete merely because the API call returned.
- Execute stays disabled during verification.
- Final message reports exact verified bag and bank totals.

Result:

- Pass/fail: PASS
- Waiting behavior observed:
- Final verification message:

### V2 — Deliberately stale plan

Use either S4 or S5.

Expected:

- Live state is used instead of imported preview state.
- No reduced or approximate transfer occurs.
- Progression stops.

Result:

- Pass/fail:
- Observed status:

### V3 — Verification interruption/failure

1. Start a valid move.
2. Immediately close the bank while the frame says it is awaiting verification.

Expected:

- No subsequent move starts.
- Current move becomes `Failed` because the exact bank result cannot be confirmed.
- The already-authorized transfer may have completed; inspect inventory manually before importing another plan.

Result:

- Pass/fail:PASS
- Did the authorized transfer physically complete:
- Final move state and status:
- Did any later move start:

---

## Result evidence to send back

For parser failures, copy:

- Exact plan text
- Red status or chat error

For transfers and workflow tests, copy or report:

- Test case ID
- Imported plan
- Starting bags and bank totals
- Preview before execution
- Status after the click
- Final move states and messages
- Final bags and bank totals
- Cursor state
- Whether any move occurred without its own click
- Any Lua error, blocked-action warning, Blizzard error, or taint popup

Screenshots of the complete `/bankx` frame are useful for UI or layout problems.
