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
| AI           | Azure OpenAI (GPT-5.3 Chat for chat/vision/scheduling) |
| Speech       | Azure OpenAI audio API (gpt-4o-transcribe-diarize) |
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

Environment variables in production are set via Azure App Settings, not `.env` files.
