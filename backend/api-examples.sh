#!/bin/bash
# MoreTime API — Example curl commands for testing
# Set BASE_URL and TOKEN before running

BASE_URL="http://localhost:3000"
TOKEN=""

# ──────────────── Auth ────────────────

# Register
curl -s -X POST "$BASE_URL/auth/register" \
  -H "Content-Type: application/json" \
  -d '{"email":"student@example.com","name":"Test Student","password":"password123"}' | jq .

# Login (save token)
TOKEN=$(curl -s -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"student@example.com","password":"password123"}' | jq -r '.accessToken')
echo "Token: $TOKEN"

# Get profile
curl -s "$BASE_URL/auth/me" \
  -H "Authorization: Bearer $TOKEN" | jq .

# ──────────────── Courses ────────────────

# Create course
curl -s -X POST "$BASE_URL/courses" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"CS310 Data Structures","color":"#3B82F6"}' | jq .

# List courses
curl -s "$BASE_URL/courses" \
  -H "Authorization: Bearer $TOKEN" | jq .

# ──────────────── Tasks ────────────────

# Create task
curl -s -X POST "$BASE_URL/tasks" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"Final Project","description":"Build a BST implementation","dueDate":"2026-04-15T23:59:00Z","priority":1,"estimatedHours":12}' | jq .

# List tasks
curl -s "$BASE_URL/tasks?sortBy=dueDate&sortOrder=asc" \
  -H "Authorization: Bearer $TOKEN" | jq .

# Update task
# curl -s -X PATCH "$BASE_URL/tasks/TASK_ID" \
#   -H "Authorization: Bearer $TOKEN" \
#   -H "Content-Type: application/json" \
#   -d '{"status":"in_progress"}' | jq .

# ──────────────── Schedule ────────────────

# Get schedule for date range
curl -s "$BASE_URL/schedule?startDate=2026-03-01&endDate=2026-03-31" \
  -H "Authorization: Bearer $TOKEN" | jq .

# Generate AI schedule
curl -s -X POST "$BASE_URL/schedule/generate" \
  -H "Authorization: Bearer $TOKEN" | jq .

# Create locked block
curl -s -X POST "$BASE_URL/schedule" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"date":"2026-03-24","startTime":"10:00","endTime":"11:15","isLocked":true,"label":"CS310 Lecture"}' | jq .

# ──────────────── Chat ────────────────

# Send chat message
curl -s -X POST "$BASE_URL/chat/message" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"message":"What should I work on today?"}' | jq .

# Create task via chat
curl -s -X POST "$BASE_URL/chat/message" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"message":"I have a CS310 project due next Friday, probably 8 hours of work"}' | jq .

# ──────────────── Files ────────────────

# Upload file
curl -s -X POST "$BASE_URL/files/upload" \
  -H "Authorization: Bearer $TOKEN" \
  -F "files=@syllabus.pdf" | jq .

# List uploads
curl -s "$BASE_URL/files" \
  -H "Authorization: Bearer $TOKEN" | jq .

# Extract tasks from uploaded file
# curl -s -X POST "$BASE_URL/files/FILE_ID/extract-tasks" \
#   -H "Authorization: Bearer $TOKEN" | jq .

# ──────────────── Voice ────────────────

# Transcribe audio
curl -s -X POST "$BASE_URL/voice/transcribe" \
  -H "Authorization: Bearer $TOKEN" \
  -F "audio=@recording.m4a" | jq .

# Voice chat (transcribe + AI response)
curl -s -X POST "$BASE_URL/voice/chat" \
  -H "Authorization: Bearer $TOKEN" \
  -F "audio=@recording.m4a" | jq .

# ──────────────── Health ────────────────

curl -s "$BASE_URL/health" | jq .
