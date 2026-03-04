# Event Image 2 Calendar

iOS app that extracts event details from poster photos using Claude vision API and creates Google Calendar events.

## Tech Stack
- **SwiftUI** (iOS 17+) with `@Observable` macro
- **Claude API** (`claude-haiku-4-5`) for vision/extraction
- **Zero SPM dependencies** — all via platform frameworks
- **XcodeGen** for project generation (`project.yml` → `.xcodeproj`)

## Project Structure
```
EventImage2Calendar/
├── EventImage2CalendarApp.swift    # App entry point
├── Models/EventDetails.swift       # @Observable + Codable event model
├── Services/
│   ├── ClaudeAPIService.swift      # Claude Messages API client (vision)
│   ├── LocationService.swift       # CLLocationManager wrapper
│   └── CalendarService.swift       # Google Calendar URL + .ics generation
├── Views/
│   ├── ContentView.swift           # NavigationStack root
│   ├── CameraView.swift            # UIImagePickerController wrapper
│   └── ResultsView.swift           # Editable event form + calendar buttons
└── Utilities/
    └── APIKeyStorage.swift         # Reads API key from Bundle (xcconfig)
```

## Key Conventions
- Architecture: Single `@Observable` class (`EventExtractor`) owns all state. No MVVM ceremony.
- API key stored in `Secrets.xcconfig` (gitignored), read via `Bundle.main.infoDictionary`
- Images resized to 1024px max dimension, JPEG quality 0.7 before API upload
- Google Calendar integration via URL scheme (no OAuth) — `calendar.google.com/calendar/render?action=TEMPLATE&...`
- Location accuracy: `kCLLocationAccuracyKilometer` (city-level, for context only)

## Development
```bash
# Regenerate Xcode project after changing project.yml
xcodegen generate

# API key setup — create Secrets.xcconfig with:
# CLAUDE_API_KEY = sk-ant-your-key-here
```

## Common Tasks
- **Change AI model**: Edit `ClaudeAPIService.swift`, swap `claude-haiku-4-5` → `claude-sonnet-4-6`
- **Adjust image compression**: Edit `UIImage.resizedForAPI()` in `CameraView.swift`
- **Modify extraction prompt**: Edit system/user prompts in `ClaudeAPIService.swift`
