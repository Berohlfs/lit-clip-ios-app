# CLAUDE.md

## Project
HighLit is a mobile app for capturing sports highlights instantly.

## Core idea
The app continuously records video and keeps only the last X seconds in a rolling buffer.

When the user taps a button, the app saves the previous X seconds as a highlight.

## Core features
- Start/stop recording session
- Maintain a rolling video buffer (e.g. last 30s)
- One-tap save of the previous buffer as a clip
- Store clips locally
- View saved clips in a simple gallery
- Export/share clips

## Core flow
1. User opens the app
2. User starts recording
3. App continuously keeps last X seconds in memory
4. User taps save
5. App saves previous X seconds as a highlight
6. User can view or share the clip

## Product principles
- One action to capture a highlight
- Zero friction during recording
- Fast and reliable saving
- Minimal UI
- Works for any sport

## Constraints
- No AI detection
- No social features
- No accounts/auth
- No advanced editing
- Keep everything local and simple

## Focus
Prioritize the recording → buffer → save → view → share loop above everything else.