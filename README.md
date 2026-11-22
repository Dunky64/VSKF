# The Driveway Butler + KerbScore

One repo with three parts:

1. **The Driveway Butler website**: services, prices, guarantee, maintenance plan, photo-quote form.
2. **Instant photo quotes**: customers upload photos and get a priced quote by email within the hour,
   24/7. The photos are analysed by an AI model running on the home PC.
3. **KerbScore**: finds streets with dirty driveways from Mapillary street imagery, for leaflet planning.

The full plan is in [`docs/PLAN.md`](docs/PLAN.md).

## Progress

| Milestone | Status |
|---|---|
| A: PC setup, GPU test | **Ready to test on the PC.** See below |
| B: Quote form, queue, worker, pricing, email, fallback, watchdog | Not started |
| C: Admin view, accuracy labelling, model benchmark | Not started |
| D: Website polish, privacy notice, terms | Not started |
| E-H: KerbScore | Not started |

## How to run this (plain English)

### On your PC
Follow [`docs/PC-SETUP.md`](docs/PC-SETUP.md). In short:
- **`setup.bat`**: installs everything (Ollama, the AI model, Python) and tests the graphics card.
  Safe to run again.
- **`diagnose.bat`**: makes a short report and sends it to your phone (ntfy app). Paste it to Claude.
- **`update.bat`**: gets the latest code and restarts the worker.

### Folder guide
| Folder | What's in it |
|---|---|
| `pc/` | Everything that runs on the home PC |
| `pc/local/` | This PC's own settings, logs and test results (never uploaded) |
| `shared/` | Things the PC and the cloud both use, e.g. the AI answer format |
| `tests/` | Automated tests |
| `docs/` | Plan and guides |

## Cost log

| Date | Item | Cost | Running total (3-month budget £100) |
|---|---|---|---|
| Nov 2026 | Claude Pro, 3 months | ~£54 | £54 |
| | Domain name (Milestone B, to buy) | ~£5-12 / year | |

Outside the budget (your decision): ICO data protection fee, about £52 a year. Check at ico.org.uk.

## Data sources and licences
- **Wikimedia Commons**: sample photos for the GPU test, downloaded on the PC. Each photo's
  author and licence are saved to `samples/photos/CREDITS.txt`. Not stored in this repo.
- More sources (Mapillary, OpenStreetMap, EPC, Land Registry, ONS) will be listed here as they're added.

## For developers
- Tests: `python -m pytest tests`
- Vision model: `qwen3-vl:8b` via Ollama. The answer schema is in `shared/ai_result.schema.json`.
