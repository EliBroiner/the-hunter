# Reality Check: Background File Scanning & Auto-Tagging

**Based only on active code.** No assumptions.

---

## 1. Trigger & Selection

### When does scanning happen?
- **Background scan:** `AutoScanManager.initialize()` (from `main.dart`) runs **once** after app start. It calls `_runBackgroundScanAndProcess()` which:
  - Optionally restores from backup (first run + backup exists).
  - Otherwise runs `FileScannerService.scanNewFilesOnly()`.
  - Then runs `FileScannerService.processPendingFiles()` for all **pending** (not yet indexed) files.
- **AI backfill:** `AiAutoTaggerService.initialize()` is called from `main()` before `runApp`. It schedules **one** delayed task: 3 seconds later it runs `processUnanalyzedFiles()`.
- **File watcher:** When a new file is detected, `FileWatcherService.onNewFile` triggers `processPendingFiles()` again (only if app is in background / not paused).

So: **Scanning** = on app open (and when file watcher sees new files). **AI tagging** = only fed by the **one-time backfill** 3 seconds after app start (see gap below).

### Which files are selected for AI analysis?
- **Only** files that reach `AiAutoTaggerService.addToQueue()`. That happens in **one place:** `processUnanalyzedFiles()` (the 3-second delayed backfill).
- Backfill uses `DatabaseService.getUnanalyzedFilesForAiBackfill()`:
  - `!isAiAnalyzed`
  - `extractedText != null && extractedText.isNotEmpty`
  - `aiStatus != 'quotaLimit'`
- So: **Any file that already has extracted text and has not been AI-analyzed** (and not quota-limited). No filter by extension in the backfill; the only “filter” is that the file must already have `extractedText` (from prior OCR/text extraction).

### Is OCR involved locally?
- **Yes.** Before anything is sent to AI:
  1. **Local path:** `AiAutoTaggerService.addToQueue()` first tries to get text: `file.extractedText`; if empty, it calls `_extractTextAsync(file)`.
  2. **`_extractTextAsync`:** Uses `TextExtractionService` for text-extractable extensions (e.g. PDF, txt), and `OCRService` for supported images. So **OCR runs on the device** for images; PDF/text use local extraction.
  3. If local text is non-empty, it then tries **local heuristic** (`KnowledgeBaseService.findMatchingCategory(text)`). Only if that returns no match is the file queued for the **server**.
- **We do not send raw file path or image bytes to the backend.** Only **text** (and document id) is sent (see below).

---

## 2. Network Payload (What leaves the phone)

### What data is actually sent to the backend?
- **Endpoint:** `POST https://the-hunter-105628026575.me-west1.run.app/api/analyze-batch`
- **Body (JSON):**
  - `userId`: string (see TODO below).
  - `documents`: list of `{ "id": string, "text": string }`.
- **`id`:** `file.path` (full path on device).
- **`text`:** Extracted text only. If missing, we use `_extractTextAsync()` (OCR for images, text extraction for PDF/text). Text is **truncated to 1000 chars** (`_maxTextLength = 1000`).
- **No image bytes, no thumbnail, no file content** — only **filename-derived fallback** when text is empty: we send `file.name` as the text.

So: **Only document id (path) + text (max 1000 chars)** leave the phone. OCR is local; the server never sees raw images.

### Is it batched?
- **Yes.** `_batchSize = 10`, `_flushInterval = 5` seconds.
- When a file is added to the queue, if `_queue.length >= 10` we call `_flushQueue()` immediately (and start the timer). Otherwise we start a 5-second timer; when it fires we flush whatever is in the queue.
- So we send **up to 10 documents per request**, not 1 and not 50.

---

## 3. Backend Logic (Inference)

### What prompt/instruction is sent to Gemini?
- **Method:** `GeminiService.AnalyzeOneDocumentAsync(DocumentPayload doc)` — one Gemini call per document in the batch.
- **Prompt (constant `DocAnalysisPrompt`):**
  ```text
  Analyze the following document text. Output JSON with: category, date (YYYY-MM-DD or null if unknown), tags (list of keywords), summary (brief).
  Return ONLY raw JSON - no markdown, no code blocks. Format: {"category":"...","date":"yyyy-MM-dd or null","tags":["..."],"summary":"..."}
  ```
- **Request:** One “content” part = prompt + `doc.Text` (the extracted text). So the model sees: “Analyze the following document text. …” + the (truncated) text.
- **Model:** `gemini-1.5-flash` (constant `GeminiDocModel`).
- Backend returns a list of `DocumentAnalysisResponse` (per doc: `documentId`, `result` with `category`, `date`, `tags`, `summary`). Quota is enforced per user (50 scans/month for free tier).

---

## 4. Save (Persistence)

### Where is it saved?
- **Isar:** `AiAutoTaggerService._updateInIsar(file)` → `DatabaseService.instance.isar.write(...)` → `isar.fileMetadatas.put(file)`.
- Updated fields: `file.category`, `file.tags`, `file.isAiAnalyzed = true`, `file.aiStatus = null` (or `'error'` / `'quotaLimit'` on failure).

### Overwrite or append?
- **Overwrite.** We set `file.tags = (result['tags'] as List<dynamic>?)?.map(...).toList()` and `file.category = result['category']`. We do **not** merge with existing tags; existing user tags are replaced for that file when AI runs.

### If AI fails?
- **403 (quota):** All files in the batch get `aiStatus = 'quotaLimit'` and are written to Isar. They are **not** re-queued.
- **Other API error or network exception:** Each file gets `aiStatus = 'error'`, is written to Isar, and **is re-queued** (`_queue.add(file)`) so a later flush will retry. No explicit retry limit in code.
- **Success:** `aiStatus = null`, `isAiAnalyzed = true`.

---

## Step-by-step flow (concise)

1. **Discovery**
   - `FileScannerService.scanNewFilesOnly()` (or backup restore / full scan) discovers files and saves them to Isar (no AI yet).
   - `processPendingFiles()` runs on **pending** files (`!isIndexed`): OCR for images, text extraction for PDF/text, local `_generateAutoTags()`, then `updateFile()`. **No call to `AiAutoTaggerService.addToQueue()`** anywhere in the scanner.

2. **Preprocessing**
   - **AI side:** Only fed by `processUnanalyzedFiles()` (3 s after app start). It loads files with `extractedText` set and `!isAiAnalyzed`, `aiStatus != 'quotaLimit'`.
   - For each file: get text (use existing `extractedText` or `_extractTextAsync` → OCR/text extraction). Try local `KnowledgeBaseService.findMatchingCategory(text)`; if match, set category/tags and write to Isar and **return** (no API call). Otherwise add file to queue with text (or `file.name` if no text). Truncate text to 1000 chars when building the batch.

3. **API call**
   - When queue has ≥10 items or after 5 s timer: `_sendBatch(batch)`.
   - POST to `/api/analyze-batch` with `userId` and `documents: [{ id: file.path, text: truncatedText }]`.
   - Backend: quota check, then `GeminiService.AnalyzeDocumentsBatchAsync()` → one Gemini call per doc with `DocAnalysisPrompt` + doc text; returns category, date, tags, summary.

4. **Storage**
   - On 200: for each response item, find file by `path == documentId`, set `category`, `tags`, `isAiAnalyzed = true`, `aiStatus = null`, then `_updateInIsar(file)`.
   - On 403: set `aiStatus = 'quotaLimit'`, write, no retry.
   - On other error/exception: set `aiStatus = 'error'`, write, re-queue for retry.

---

## Gaps and “not fully real” indicators

| Item | Where | Detail |
|------|--------|--------|
| **TODO / Hardcoded userId** | `ai_auto_tagger_service.dart` L137 | `final userId = 'anonymous'; // TODO: AuthService.instance.currentUser?.uid` — quota is per “user” but all clients currently send the same anonymous id. |
| **New files never queued for AI in same session** | Flow | `addToQueue()` is **only** called from `processUnanalyzedFiles()` (once, 3 s after start). `FileScannerService.processPendingFiles()` **never** calls `addToQueue()`. So files that get **indexed in the current run** (OCR/text extraction) are **not** added to the AI queue until the **next** app launch (when backfill runs again). |
| **Backend date/summary ignored** | Client | Backend returns `date` and `summary`; client only uses `category` and `tags`. `date` and `summary` are not persisted. |
| **Tags overwrite** | Client | AI result overwrites `file.tags` (and `file.category`). No merge with existing user-defined tags. |
| **No retry limit** | Client | On error we re-queue; there is no max retry count, so a permanently failing file can be retried indefinitely. |

---

## Summary table

| Question | Answer |
|----------|--------|
| When does scanning happen? | On app open (background) + when file watcher detects new files. |
| When does AI run? | Only via backfill 3 s after app start (files that already have `extractedText` and `!isAiAnalyzed`). Newly indexed files in the same session are not sent to AI until next launch. |
| OCR before AI? | Yes, on device (OCR for images, text extraction for PDF/text). Only text (and path as id) is sent. |
| What is sent? | `userId` + list of `{ id: file.path, text: truncated text (max 1000 chars) }`. No image/raw file. |
| Batched? | Yes; up to 10 documents per request, flush after 5 s if not full. |
| Gemini prompt? | “Analyze the following document text. Output JSON with: category, date, tags, summary…” + doc text. |
| Where saved? | Isar `fileMetadatas`; overwrites `category` and `tags` for that file. |
| Retry on failure? | Yes (re-queue on non-403 error); no retry limit. |
