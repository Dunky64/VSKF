# Plan: The Driveway Butler + instant photo quotes + KerbScore

Status: **draft, waiting for your OK** (22 Nov 2026)

## How the pieces fit together

```
 Customer's phone                     Cloud (all free tiers)                    Your PC (home worker)
 ────────────────                     ──────────────────────                    ─────────────────────
 Website + quote form  ──upload──►  Supabase: database + photo storage  ◄──polls every 30 s──  Python worker
 (Cloudflare Pages)                  Edge functions:                           (outbound only, no open ports)
   • resizes photos                    • submit-quote (checks, strips EXIF,          │
   • strips EXIF                         rate limit, Turnstile bot check)            ▼
   • Turnstile bot check               • submit-result (prices + emails)         Ollama + qwen3-vl:8b
                                       • watchdog (runs every minute)            on the RX 9070
                                     Resend (email)  ntfy (push to your phone)
```

Key design choices:

- **The PC never sets prices and never holds the email key.** It only sends the AI's JSON back.
  The cloud checks the JSON, runs the pricing rules from one config file (`config/pricing.json`)
  and sends the email. That means one pricing engine is used both for normal quotes and for
  fallback quotes, so they can't drift apart.
- **The PC only has a "worker" key.** It can read new requests and write results. Nothing else.
- **Watchdog:** a scheduled job in Supabase runs every minute. Any request older than 45 minutes
  without a quote, or any request arriving while the PC's heartbeat is older than 15 minutes,
  gets an instant fallback quote from the form answers. An automated test proves no request
  goes past 60 minutes.
- **Deploying from your phone:** you paste each service's keys into GitHub once (Settings → Secrets).
  After that, GitHub Actions deploys the website and the cloud functions every time I push code.
  You never type commands.
- **Your PC:** `setup.bat`, `update.bat`, `diagnose.bat`. Double-click only.

## Milestones

| | What you get | What you have to do |
|---|---|---|
| **A** | `setup.bat` + `diagnose.bat`: install Ollama, prove it's using the RX 9070 (not the CPU), pull `qwen3-vl:8b`, test 5 sample driveway photos, print seconds per image and graphics memory used. | Download the repo, double-click `setup.bat`, then `diagnose.bat`, paste the report back to me. |
| **B** | Quote form, queue, home worker, pricing rules, email + phone alerts, fallback quote, watchdog, 60-minute test. Deployed with a link to test from your phone. | Create free accounts (Supabase, Cloudflare, Resend, ntfy app), paste keys into GitHub. I'll give exact steps. |
| **C** | Admin view (phone-friendly, password-protected): quotes, photos, AI fields, flags, adjust-and-resend, booked/done buttons. Weekly accuracy labelling page. Benchmark script to compare vision models. | Try it, tell me what's awkward. |
| **D** | Website polish: services, prices, guarantee, maintenance plan, privacy notice, terms, 90-day photo deletion job. | Review the wording (it's customer-facing and legal). |
| **E** | KerbScore step 1: Mapillary coverage report for the HD postcode area (map, image counts, ages). **Stop point** if coverage is thin. | Get a free Mapillary token. |
| **F** | Area data (OSM, EPC, Land Registry, ONS), neighbourhood ranking, top 3–5 recommendation. | Approve the area before the big batch. |
| **G** | Overnight batch scoring on your PC, street totals only (no per-house records), map, ranked list. LIA draft + privacy notice. | Review the LIA. |
| **H** | Leaflet route planner, per-street QR codes, A5 leaflet PDF, lead tracker, Facebook ads CSV. | Print leaflets. |

After every milestone: deployed link, updated cost log and "how to run this" in the README.

## Things I can't guarantee (being honest)

- If Supabase or the email service itself is down, nothing can send. The 60-minute test proves
  *our* system always produces a quote in time; it can't control someone else's outage.
- Free Supabase projects pause after 7 days of no activity. Your PC's heartbeat every minute
  keeps it awake; the watchdog schedule does too.
- Free-tier limits that matter: Supabase 1 GB photo storage (photos are resized to ~300 KB, so
  roughly 800 quote requests before the 90-day deletion matters), Resend 100 emails/day.
  Both are far above what a part-time business will need in its first year.

## Expected costs (first 3 months)

| Item | Cost | Notes |
|---|---|---|
| Claude Pro | ~£54 | You already have it |
| Domain name (e.g. `thedrivewaybutler.co.uk`) | ~£5–12 / year | **Needs your OK.** Strongly recommended: free email services only send to customers from a domain you own. |
| Supabase, Cloudflare Pages, Turnstile, Resend, ntfy, Mapillary, GitHub | £0 | Free tiers |
| ICO data protection fee | ~£52 / year | **Legal, not software.** Most businesses handling customer data must pay it. Please check at ico.org.uk. Your call whether it counts against this budget. |
