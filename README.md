# MoreTime

AI-powered study schedule optimizer for students. MoreTime helps you manage coursework, extract tasks from syllabi, chat with an AI assistant that understands your workload, and generate optimized day-by-day study plans — all from a native iOS app backed by a Node.js API.

---

## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Supabase Setup](#supabase-setup)
  - [Backend Setup](#backend-setup)
  - [iOS Setup](#ios-setup)
- [Environment Variables](#environment-variables)
- [API Reference](#api-reference)
- [Database Schema](#database-schema)
- [Tests](#tests)
- [Deployment](#deployment)

---

## Features

### Task Management

- Create, edit, and delete tasks with due dates, priority levels (1–5), estimated hours, and course assignments
- Group tasks by course with color-coded indicators
- Sort by due date, priority, or creation date
- Swipe-to-complete and swipe-to-delete gestures
- Mark tasks as pending, in-progress, or completed
- Optional **learning debrief** after you mark a task complete (confidence, hardest part, optional “revisit” note) — saved to your profile for Chat context; see **Learning reflections** below

### Learning reflections

- Short post-completion reflection (from **Tasks** swipe-to-complete or **Task detail** when moving to completed); **Skip** saves nothing; **Save** appends to profile **`preferences.learningDebriefs`** (JSON array, last 25 entries)
- **Settings → Past reflections**: browse saved debriefs, pull to refresh from the server, or **Clear all** to remove them from your profile
- The chat backend injects recent reflections into the assistant **system prompt** so replies can personalize study advice (no separate ML model or agent)

### AI Chat Assistant

- Context-aware chat that knows your tasks, schedule, and courses
- Uses **recent learning reflections** from your profile when present (see **Learning reflections** above)
- **Paperclip attachments:** upload assignment PDFs/DOCX/images from chat; after parsing, the assistant uses the document text to schedule tasks (same upload + parse pipeline as **Files**)
- Automatically detects and creates tasks from natural conversation (e.g., "I have a CS310 paper due Friday")
- Auto-generates schedule blocks whenever a task is created via chat
- Persistent conversation history with session management
- Suggestion chips for quick prompts

### Document Upload & Task Extraction

- Upload PDF, DOCX, TXT, or image files (syllabi, assignment sheets)
- AI-powered document classification (syllabus vs. single assignment)
- Syllabi: extracts all assignments, exams, and deadlines with estimated hours
- Assignments: breaks down a single deliverable into actionable subtasks spread across available days
- OCR fallback for scanned PDFs and images via GPT-4o vision

### Schedule Generation

- AI analyzes all pending tasks, deadlines, priorities, and locked blocks to produce an optimal study plan
- Respects student preferences (study hours, max hours/day, break duration)
- Never schedules over locked blocks (classes, work, etc.)
- Validates generated blocks for time conflicts and format correctness with up to 3 retry attempts
- Auto-escalates priority of overdue tasks
- Each block includes a specific label describing what to work on during that session

### Voice Input

- Record audio and send to AI chat via voice
- Azure OpenAI transcription (gpt-4o-transcribe-diarize)
- Real-time audio level visualization with waveform display

### Calendar View

- Monthly calendar grid with color-coded indicators: **circles** for schedule blocks, **small squares** for tasks that have a **due date** but no matching block (deduped when a block already links the same task)
- Day detail separates **Scheduled** (time blocks from `/schedule`: classes and planned study sessions) from **Due** (tasks from your **Tasks** tab due that day without a matching block). If your task list is empty, you may still see **Scheduled** rows from classes or generated schedule — those are not task-list items. Tap a task under **Due** to open its detail
- Toolbar **Clear** menu: **Clear all schedule** (removes every block, including locked class times) and **Clear current day** (removes all blocks on the selected date and deletes pending/in-progress tasks due that local day)
- **Clear Schedule** (toolbar): deletes **non-locked** blocks on the server, refetches the calendar, then updates the UI. Locked class blocks stay. Tasks with due dates can still appear under **Due** until you edit or remove those tasks
- Navigate between months, jump to today
- Locked blocks (recurring classes) shown with lock icon

### Semester Heat Map

- **Semester** tab: upload multiple syllabi (PDF/DOCX), map files to course names, pick semester dates, generate an AI **week-by-week** workload view (intensity, crunch weeks, events list)
- **Apply to Calendar** creates tasks from plan events via `POST /tasks`
- **One plan per user**: the generated `SemesterPlan` is stored in profile **`preferences.semesterPlan`** (JSON string). **New Plan** clears local state and removes that preference via `PATCH /auth/me`
- Reopening the Semester tab restores the saved plan after `GET /auth/me` (if present)

### Course Management & Class Schedule (Settings)

- **Settings → Courses & class schedule** (sheet): manage courses, add recurring **locked** class blocks to the calendar (with **Repeat until** end date for weekly repetition)
- **Delete course**: from the course edit sheet (**Delete course**), swipe-to-delete on the list, or clear the class picker when that course is removed
- **Delete scheduled class**: open the class in the editor (**Delete from schedule**) or swipe left on a row in **Scheduled classes (locked)**

### Course Management (Tasks & Blocks)

- Create courses with custom names and hex colors
- Tasks and schedule blocks can be associated with courses (optional for some tasks)
- Task count displayed per course in the course list

---

## Architecture

```
┌──────────────────┐         ┌──────────────────────┐
│   iOS App        │  HTTP   │   Express API         │
│   (SwiftUI)      │ ◄─────► │   (Node.js + TS)      │
│                  │         │                        │
│  @Observable     │         │  Routes → Services     │
│  Stores ──► API  │         │       ↓                │
│  Client          │         │  ┌──────────┐          │
│                  │         │  │ Supabase │ Auth + DB │
│  Keychain tokens │         │  └──────────┘          │
│                  │         │  ┌──────────────────┐  │
│                  │         │  │ Azure OpenAI     │  │
│                  │         │  │ Chat, Vision,    │  │
│                  │         │  │ Scheduling,      │  │
│                  │         │  │ Transcription    │  │
│                  │         │  └──────────────────┘  │
└──────────────────┘         └────────────────────────┘
```

### Backend

- **Express** routes handle HTTP requests with Zod validation middleware
- **Supabase** for authentication (Admin API for user creation, session tokens for auth) and Postgres database
- **Azure OpenAI** for all AI features: chat completions, document parsing, schedule generation, image OCR, and audio transcription
- **Service layer** separates business logic (chat context building, schedule optimization, file parsing, learning-debrief formatting for chat) from route handlers
- **snake_case ↔ camelCase** transform layer between Supabase (snake) and API responses (camel)
- Rate limiting: 200 req/15 min global; stricter limiter (20 req/min) on `/chat`, `/files`, and `/voice` (AI-heavy routes)

### iOS

- **@Observable stores** (`AuthStore`, `TaskStore`, `ScheduleStore`, `ChatStore`, `SemesterStore`) manage state and are injected via SwiftUI's `.environment()`
- **APIClient** singleton handles all networking with automatic token refresh on 401 responses
- **KeychainHelper** stores auth tokens securely
- **ErrorLogger** captures and surfaces API errors via toast banners and a debug log
- **Profile preferences** (`PATCH /auth/me`): merged client-side; used for study-time prefs, persisted **semester plan** (`semesterPlan` key), and **learning debriefs** (`learningDebriefs` array)
- Tab bar: **Calendar**, **Tasks**, **Chat**, **Semester**, **Settings** — switching to Calendar refreshes tasks and loaded schedule range
- Targets iOS 17+ using `@Observable` (not Combine); tab bar uses iOS 17–compatible `.tabItem` / `.tag` APIs

---

## Tech Stack

| Layer        | Technology                                       |
| ------------ | ------------------------------------------------ |
| iOS App      | Swift, SwiftUI, SwiftData, iOS 17+               |
| Backend      | Node.js 24+, Express, TypeScript                 |
| Database     | Supabase (PostgreSQL)                            |
| Auth         | Supabase Auth (Admin API + session tokens)       |
| AI           | Azure OpenAI (GPT-4o for chat/vision/scheduling) |
| Speech       | Azure OpenAI audio API (`gpt-4o-transcribe-diarize`; same endpoint/key as chat) |
| File Parsing | pdf-parse, mammoth (DOCX), GPT-4o vision (OCR)   |
| Validation   | Zod                                              |
| Testing      | Vitest (`backend/tests`)                         |
| Deployment   | Azure Web App via GitHub Actions                 |

---

## Project Structure

```
MoreTime/
├── backend/
│   ├── src/
│   │   ├── index.ts                  # Express app entry point
│   │   ├── routes/
│   │   │   ├── auth.ts               # Register, login, refresh, logout, profile
│   │   │   ├── courses.ts            # CRUD for courses
│   │   │   ├── tasks.ts              # CRUD for tasks
│   │   │   ├── schedule.ts           # Schedule blocks + AI generation
│   │   │   ├── chat.ts               # AI chat messages
│   │   │   ├── files.ts              # File upload, task extraction, semester-plan API
│   │   │   └── voice.ts              # Audio transcription + voice chat
│   │   ├── services/
│   │   │   ├── ai.ts                 # Azure OpenAI (chat, extract, schedule, semester plan)
│   │   │   ├── chat.ts               # Chat context builder + action parser
│   │   │   ├── scheduling.ts         # Schedule generation, validation, semester week grouping
│   │   │   ├── fileParser.ts         # PDF, DOCX, TXT, image parsing
│   │   │   └── voice.ts              # Audio transcription via Azure
│   │   ├── middleware/
│   │   │   ├── auth.ts               # Bearer token auth guard (Supabase)
│   │   │   ├── validate.ts           # Zod request validation
│   │   │   └── errorHandler.ts       # Global error handler
│   │   └── utils/
│   │       ├── supabase.ts           # Supabase client singleton
│   │       ├── azure-openai.ts       # OpenAI client singleton
│   │       ├── env.ts                # Environment variable validation
│   │       ├── errors.ts             # Custom error classes
│   │       ├── transform.ts          # snake_case ↔ camelCase
│   │       └── learningDebriefs.ts   # Format stored reflections for chat system prompt
│   ├── tests/                        # Vitest (validation, scheduling)
│   ├── supabase-migration.sql        # Database schema + RLS policies
│   ├── package.json
│   └── tsconfig.json
│
├── ios/
│   └── MoreTime/
│       ├── MoreTimeApp.swift          # App entry point
│       ├── Views/
│       │   ├── RootView.swift         # Auth routing (login vs main)
│       │   ├── LoginView.swift        # Sign in + registration
│       │   ├── MainTabView.swift      # Tab bar (Calendar, Tasks, Chat, Semester, Settings)
│       │   ├── CalendarView.swift     # Calendar + merged due tasks + day detail
│       │   ├── SemesterHeatMapView.swift  # Semester heat map + apply to calendar
│       │   ├── TaskListView.swift     # Task list with grouping + sorting
│       │   ├── TaskDetailView.swift   # Task edit/create form
│       │   ├── ChatView.swift         # AI chat interface
│       │   ├── VoiceInputView.swift   # Voice recording UI
│       │   ├── SettingsView.swift     # Settings, study prefs, courses & class schedule sheet
│       │   ├── LearningDebriefSheet.swift  # Post-completion reflection form
│       │   ├── PastReflectionsView.swift   # Settings: list of saved debriefs
│       │   ├── ScheduleGenerateView.swift  # Schedule generation UI
│       │   ├── FileUploadView.swift   # File upload + task extraction
│       │   └── CourseManagementView.swift   # Course CRUD
│       ├── Stores/
│       │   ├── AuthStore.swift        # Auth state management
│       │   ├── TaskStore.swift        # Tasks + courses state
│       │   ├── ScheduleStore.swift    # Schedule blocks state
│       │   ├── ChatStore.swift        # Chat messages state
│       │   └── SemesterStore.swift    # Semester plan, file upload helpers, apply-to-tasks
│       ├── Services/
│       │   ├── APIClient.swift        # HTTP client with token refresh
│       │   ├── KeychainHelper.swift   # Secure token storage
│       │   ├── AudioRecorder.swift    # AVAudioRecorder wrapper
│       │   └── ErrorLogger.swift      # Error capture + toast banner
│       ├── Models/
│       │   ├── APIModels.swift        # Codable DTOs for all endpoints
│       │   └── CachedModels.swift     # SwiftData models (local cache)
│       └── Components/
│           ├── ColorExtension.swift   # Color(hex:) initializer
│           └── ErrorBanner.swift      # Global error overlay modifier
│
├── .github/workflows/
│   └── main_moretime.yml              # CI/CD pipeline
└── .gitignore
```

---

## Getting Started

### Prerequisites

- **Node.js** 24+ and npm
- **Xcode** 15+ with iOS 17+ SDK
- A **Supabase** project ([supabase.com](https://supabase.com))
- An **Azure OpenAI** resource with a GPT-4o deployment

### Supabase Setup

1. Create a new project at [supabase.com/dashboard](https://supabase.com/dashboard)

2. Open the **SQL Editor** and run the migration file to create all tables, indexes, triggers, and RLS policies:

```sql
-- Copy and paste the contents of backend/supabase-migration.sql
```

This creates: `profiles`, `courses`, `tasks`, `schedule_blocks`, `file_uploads`, `chat_messages`

It also creates a trigger (`on_auth_user_created`) that automatically inserts a `profiles` row whenever a new user signs up via Supabase Auth.

3. Go to **Project Settings → API** and copy:
   - **Project URL** → `SUPABASE_URL`
   - **service_role secret** key → `SUPABASE_SERVICE_ROLE_KEY` (used by the Node API only; keep server-side)

The backend does **not** require the Supabase anon key. Use the anon key only if you add a Supabase client directly in a mobile or web app.

### Backend Setup

```bash
cd backend
npm install   # runs `tsc` via postinstall to emit `dist/`
npm run dev   # starts dev server with hot reload (default port 3000)
```

Set the variables from [Environment Variables](#environment-variables) in your shell or IDE before starting the server. The backend reads `process.env` only; it does not load a `.env` file unless you add a loader (for example `dotenv`) or configure your editor to inject env vars.

The dev server runs at `http://localhost:3000`. Test with:

```bash
curl http://localhost:3000/health
```

### iOS Setup

1. Open `ios/MoreTime.xcodeproj` in Xcode
2. Set the API base URL in [`ios/MoreTime/Services/APIClient.swift`](ios/MoreTime/Services/APIClient.swift) (`baseURL`) — e.g. your deployed Azure Web App or `http://localhost:3000` for a local backend
3. Build and run on the iOS Simulator (or a physical device)

#### Dev Bypass (Optional)

For development without authentication, set `DEV_BYPASS_AUTH=true` in the environment that runs the API (same as your other backend variables). The iOS app has a corresponding `#if DEBUG` block in `AuthStore.swift` that auto-authenticates with a dev user. Remove or disable this block when testing real auth flows.

---

## Environment Variables

Required variables are checked in `backend/src/utils/env.ts` the first time the API needs Supabase or Azure OpenAI (lazy init). `DEV_BYPASS_AUTH` and `NODE_ENV` are read directly from `process.env`. Supply variables via your shell, IDE run configuration, or hosting provider (e.g. Azure App Settings). They are **not** loaded from a `.env` file unless you add that yourself.

| Variable                       | Required | Description                                                    |
| ------------------------------ | -------- | -------------------------------------------------------------- |
| `SUPABASE_URL`                 | Yes      | Your Supabase project URL (e.g., `https://xxx.supabase.co`)    |
| `SUPABASE_SERVICE_ROLE_KEY`    | Yes      | Supabase service role key (secret — server-side only)          |
| `AZURE_OPENAI_ENDPOINT`        | Yes      | Azure OpenAI resource endpoint (base URL)                      |
| `AZURE_OPENAI_API_KEY`         | Yes      | Azure OpenAI API key (chat, vision, scheduling, transcription) |
| `AZURE_OPENAI_DEPLOYMENT_NAME` | No       | Chat / vision deployment name (default: `gpt-4o`)            |
| `PORT`                         | No       | Server port (default: `3000`)                                  |
| `DEV_BYPASS_AUTH`              | No       | Set to `true` to skip auth in development ([Dev Bypass](#dev-bypass-optional)) |
| `NODE_ENV`                     | No       | Set to `production` to hide error details in API responses     |

---

## API Reference

All endpoints (except auth and health) require a `Bearer <token>` header. Tokens are Supabase session access tokens obtained from login/register.

### Auth — `/auth`

| Method  | Path        | Body                                   | Response                                                                                                                                                          |
| ------- | ----------- | -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `POST`  | `/register` | `{ email, name, password, timezone? }` | `{ user, accessToken, refreshToken }`                                                                                                                             |
| `POST`  | `/login`    | `{ email, password }`                  | `{ user, accessToken, refreshToken }`                                                                                                                             |
| `POST`  | `/refresh`  | `{ refreshToken }`                     | `{ accessToken, refreshToken }`                                                                                                                                   |
| `POST`  | `/logout`   | —                                      | `{ message }`                                                                                                                                                     |
| `GET`   | `/me`       | —                                      | `UserProfile`                                                                                                                                                     |
| `PATCH` | `/me`       | `{ name?, timezone?, preferences? }`   | `UserProfile` (full `preferences` JSON is replaced with the merged object from the client; optional `semesterPlan` string for the semester heat map; optional `learningDebriefs` array of reflection objects) |

### Courses — `/courses`

| Method   | Path   | Body                           | Response                         |
| -------- | ------ | ------------------------------ | -------------------------------- |
| `GET`    | `/`    | —                              | `[Course]` (includes task count) |
| `GET`    | `/:id` | —                              | `Course` (includes tasks)        |
| `POST`   | `/`    | `{ name, color?, metadata? }`  | `Course`                         |
| `PATCH`  | `/:id` | `{ name?, color?, metadata? }` | `Course`                         |
| `DELETE` | `/:id` | —                              | `204`                            |

### Tasks — `/tasks`

| Method   | Path     | Body / Query                                                                        | Response                                       |
| -------- | -------- | ----------------------------------------------------------------------------------- | ---------------------------------------------- |
| `GET`    | `/`      | Query: `courseId?`, `status?`, `sortBy?`, `sortOrder?`                              | `[TaskItem]`                                   |
| `GET`    | `/:id`   | —                                                                                   | `TaskItem` (includes course + schedule blocks) |
| `POST`   | `/`      | `{ courseId?, title, description?, dueDate?, priority?, estimatedHours?, status? }` | `TaskItem`                                     |
| `PATCH`  | `/:id`   | Same fields, all optional                                                           | `TaskItem`                                     |
| `DELETE` | `/:id`   | —                                                                                   | `204`                                          |
| `DELETE` | `/clear` | —                                                                                   | `{ removed }`                                  |
| `DELETE` | `/due-in-day` | Query: `start`, `end` (ISO-8601 instants, half-open `[start,end)`)            | `{ removed }` — pending / in-progress tasks with `due_date` in range |

### Schedule — `/schedule`

| Method   | Path        | Body / Query                                               | Response                                                                                                   |
| -------- | ----------- | ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `GET`    | `/`         | Query: `startDate`, `endDate` (YYYY-MM-DD)                 | `[ScheduleBlock]`                                                                                          |
| `POST`   | `/`         | `{ taskId?, date, startTime, endTime, isLocked?, label? }` | `ScheduleBlock`                                                                                            |
| `PATCH`  | `/:id`      | Same fields, all optional                                  | `ScheduleBlock`                                                                                            |
| `DELETE` | `/:id`      | —                                                          | `204`                                                                                                      |
| `DELETE` | `/clear`    | —                                                          | `{ removed }` — non-locked blocks only (`is_locked = false`)                                               |
| `DELETE` | `/clear-all` | —                                                        | `{ removed }` — all blocks for the user (locked + generated)                                               |
| `DELETE` | `/day`      | Query: `date` (YYYY-MM-DD)                                 | `{ removed }` — all blocks on that calendar date                                                           |
| `POST`   | `/generate` | —                                                          | `{ blocksCreated, blocksRemoved, blocks, warnings }`                                                       |

### Chat — `/chat` (rate limited: 20/min)

| Method | Path       | Body                      | Response                                               |
| ------ | ---------- | ------------------------- | ------------------------------------------------------ |
| `POST` | `/message` | `{ message?, sessionId?, fileIds? }` — provide a non-empty `message` and/or at least one `fileId` (max 5) | `{ sessionId, response, action?, scheduleGenerated? }` |

**Attachments:** Upload files with `POST /files/upload`, poll `GET /files/:id` until `parseStatus` is `completed`, then send their IDs in `fileIds`. The server injects parsed text into the model for that turn only (not stored in full in chat history). Chat messages store a short `[Attachments: …]` line instead.

**Context:** The assistant system prompt includes your pending tasks, today’s blocks, courses, and **recent learning reflections** from `profiles.preferences.learningDebriefs` when present (formatted in `backend/src/utils/learningDebriefs.ts`).

The AI may return an `action` of type `task_created` with the created task data. When this happens, the schedule is automatically regenerated in the background.

### Files — `/files` (rate limited: 20/min with other AI routes)

| Method   | Path                 | Body                                                                     | Response                                                          |
| -------- | -------------------- | ------------------------------------------------------------------------ | ----------------------------------------------------------------- |
| `POST`   | `/upload`            | Multipart: `files` + optional `courseId`                                 | `[FileUploadResponse]`                                            |
| `GET`    | `/`                  | —                                                                        | `[FileUploadResponse]`                                            |
| `GET`    | `/:id`               | —                                                                        | `FileUploadResponse`                                              |
| `DELETE` | `/:id`               | —                                                                        | `204`                                                             |
| `POST`   | `/semester-plan`     | `{ fileIds: string[], semesterStart, semesterEnd }` (dates `YYYY-MM-DD`) | `{ weeks, crunchWeeks, totalEvents, semesterStart, semesterEnd }` |
| `POST`   | `/:id/extract-tasks` | `{ dueDate? }`                                                           | `{ extractedCount, tasks, documentType }`                         |

Uploaded files are parsed asynchronously. Poll `GET /:id` until `parseStatus` is `completed`. The extract endpoint auto-detects whether the document is a syllabus (extracts all assignments) or a single assignment (breaks it into subtasks).

### Voice — `/voice` (rate limited: 20/min)

| Method | Path          | Body                                      | Response                                 |
| ------ | ------------- | ----------------------------------------- | ---------------------------------------- |
| `POST` | `/transcribe` | Multipart: `audio`                        | `{ text }`                               |
| `POST` | `/chat`       | Multipart: `audio` + optional `sessionId` | `{ transcription, sessionId, response }` |

### Health

| Method | Path      | Response                      |
| ------ | --------- | ----------------------------- |
| `GET`  | `/health` | `{ status: "ok", timestamp }` |

---

## Database Schema

All tables use UUIDs as primary keys. Row Level Security (RLS) is enabled on every table — users can only access their own data.

| Table             | Key Columns                                                                                     | Notes                                                                                                                                   |
| ----------------- | ----------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `profiles`        | `id` (FK → auth.users), `email`, `name`, `timezone`, `preferences` (JSONB)                      | Auto-created via trigger on auth signup; may include `semesterPlan` (string) for the saved heat map and `learningDebriefs` (array) for post-task reflections used in chat |
| `courses`         | `id`, `user_id`, `name`, `color`                                                                |                                                                                                                                         |
| `tasks`           | `id`, `user_id`, `course_id`, `title`, `due_date`, `priority`, `estimated_hours`, `status`      | `course_id` set null on course delete                                                                                                   |
| `schedule_blocks` | `id`, `user_id`, `task_id`, `course_id`, `date`, `start_time`, `end_time`, `is_locked`, `label` | Optional `course_id` → `courses` for class blocks; API embeds `classCourse` when FK `schedule_blocks_course_id_fkey` exists in Supabase |
| `file_uploads`    | `id`, `user_id`, `course_id`, `original_name`, `storage_path`, `mime_type`, `file_size`, `parsed_content`, `parse_status`, `parsed_at` | Upload metadata + async parse pipeline; status: pending → parsing → completed/failed                                                  |
| `chat_messages`   | `id`, `user_id`, `role`, `content`, `session_id`, `timestamp`                                   | Roles: user, assistant                                                                                                                  |

See `backend/supabase-migration.sql` for the complete schema, indexes, trigger function, and RLS policies.

---

## Tests

From the `backend` directory:

```bash
npm test        # run once (Vitest)
npm run test:watch
```

---

## Deployment

The backend deploys to **Azure Web App** via GitHub Actions when `main` changes under `backend/**` or when the workflow file `.github/workflows/main_moretime.yml` changes. You can also run the workflow manually (**Actions → workflow_dispatch**).

### CI/CD Pipeline (`.github/workflows/main_moretime.yml`)

1. Checkout code
2. Set up Node.js 24.x
3. `npm install` → `npm run build` → `npm prune --omit=dev`
4. Remove `.env` files (secrets are configured in Azure App Settings)
5. Upload build artifact
6. Deploy to Azure Web App `moretime` (Production slot) using OIDC auth

### Production URLs

- **API**: `https://moretime-gdbwhjgfdxeyhtfw.canadacentral-01.azurewebsites.net`
- **Health check**: `GET /health`

Environment variables in production are set via Azure App Settings, not `.env` files.
