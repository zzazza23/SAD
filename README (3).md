# Scholarship Monitoring and Academic Compliance System
SAD Midterm Lab Exam, Section A. Student: Crizza D. Farofaldino (M-008671), BSIT 3.
Stack: HTML, CSS, JavaScript, Supabase (Postgres + Auth + Row Level Security). Synthetic data only.

## Files
- `schema.sql` - tables, Row Level Security policies, database functions, seed records A01 to A06
- `index.html` - the whole app (login, scholar screens, staff screens)
- `config.js` - Supabase URL and anon key
- `TEST_RESULTS.md` - TC01 to TC10 results table

## Setup
1. Create a free project at supabase.com.
2. Go to Authentication > Users > Add user. Create two users with "Auto Confirm User" ON:
   - `staff@test.local` (staff)
   - `scholar@test.local` (scholar, becomes record A01)
   Choose your own passwords. Do not put them in the code or screenshots.
3. Go to SQL Editor, paste all of `schema.sql`, and click Run. (Run it once on an empty project.)
4. Go to Project Settings > API. Copy the Project URL and the **anon public** key into `config.js`.
   Environment variable names used: `SUPABASE_URL`, `SUPABASE_ANON_KEY`. Never use the service-role key.

## Run
In this folder run `python -m http.server 8000`, then open http://localhost:8000
(or open the folder in VS Code and use Live Server). Hosting is optional (GitHub Pages works).

## How it works
- **Scholar** logs in, submits grades, sees status, corrects Returned records.
- **Staff** logs in, registers scholars, verifies or returns evidence, evaluates, approves or holds renewal, uses the dashboard, search, filters, and history log.
- All writes go through database functions that check the user's role. Tables have no direct write access. Scholars can only read their own rows (RLS).
- Policy thresholds are read from the `programs` table, not from code.
- Three separate fields: `verification_status`, `compliance_result`, `renewal_decision`.

## Known behavior and defects
- Only 2 login accounts exist. A02 to A06 are seeded records without logins. A scholar registered by staff can log in only if the same email already exists in Supabase Auth.
- A resubmission keeps the original submission timestamp (the correction time is in the history log).
- Fill in any defects found during testing here: (none found yet).

## Test accounts
Supplied privately to the instructor.
