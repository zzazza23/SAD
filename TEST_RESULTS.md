# Test Results (TC01 to TC10)
Run each test, then fill in Actual, Pass/Fail, and Evidence (screenshot file name). Report failures honestly.

| ID | Input or action | Expected result | Actual result | Pass/Fail | Evidence |
|---|---|---|---|---|---|
| TC01 | Staff evaluate A01 (GWA 1.75, exact deadline) | Compliant | | | |
| TC02 | Staff evaluate A02 (GWA 1.76) | With Deficiency, GWA reason | | | |
| TC03 | Staff evaluate A03 (Community, 1 dropped) | Compliant | | | |
| TC04 | Staff evaluate A04 (14 units, 1 INC) | With Deficiency: insufficient units and incomplete grade | | | |
| TC05 | Staff evaluate A05 (1 failed, 1 minute late) | With Deficiency: failing subject and late submission | | | |
| TC06 | Click Evaluate, then Approve on A06 (Pending) | Both blocked with a message | | | |
| TC07 | Scholar submits duplicate semester; GWA 0.50; negative count | Each rejected with a clear message | | | |
| TC08 | Log in as scholar: read another record (browser console) and call verify_submission | No other data returned; verify denied "Staff only." | | | |
| TC09 | Staff Return a record with reason; scholar Corrects and resubmits; refresh | Pending verification; history kept | | | |
| TC10 | Staff Approve A01 (Compliant), Hold A02 (deficient); scholar tries decide_renewal | Approved and Held saved; scholar denied | | | |screenshots/4_renewal.png

## TC08 console commands (run while logged in as the scholar, F12 > Console)
```js
await db.from("submissions").select("*")                      // only your own row (A01)
await db.rpc("verify_submission",{p_id:2,p_status:"Verified",p_reason:null})  // error: Staff only.
await db.rpc("decide_renewal",{p_id:1,p_decision:"Approved",p_note:"x"})      // error: Staff only.
```
Notes: TC09 needs a record to return. Use A06 (Pending): Return it as staff, but A06 has no login, so run the correction with `scholar@test.local` by first submitting a new record there (use academic year 2025-2026), returning it, then correcting it.
