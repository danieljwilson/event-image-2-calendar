# Beta Testing Plan

## Goal
50-100 active TestFlight testers providing regular feedback over 4 weeks before public launch.

## Recruitment Channels

### Tier 1: High-conversion (start here)
- [ ] **Personal network** — friends, academic colleagues, lab members, department listservs
- [ ] **Reddit** — post in r/iOSBeta, r/apple, r/productivity, r/concerts, r/iphoneapps seeking beta testers
- [ ] **Twitter/X** — demo video + TestFlight link, use hashtags #iosdev #betatesters #indiedev
- [ ] **Hacker News** — "Show HN: Event Snap — turns event posters into calendar events" (weekday 9-11am ET)

### Tier 2: Beta directories
- [ ] **BetaList.com** — free listing, good for early adopters
- [ ] **BetaPage.co** — another beta directory
- [ ] **Product Hunt "Upcoming"** — reserve listing early, build anticipation

### Tier 3: Targeted communities
- [ ] **University subreddits** — target event-heavy campuses (large state schools, urban universities)
- [ ] **University Discord servers** — student org servers, event planning channels
- [ ] **Local Facebook groups** — events, concerts, community calendars in your area
- [ ] **iOS developer communities** — they'll appreciate the technical angle and give quality feedback

## Feedback Infrastructure

### Already built (in-app)
- Screenshot-triggered feedback prompt (TestFlight builds)
- Debug log viewer accessible from Settings
- In-app feedback submission via FeedbackService
- Crash reporting via MetricKit (CrashReportingService)

### To set up
- [ ] External feedback form (Google Form or Tally) — link from onboarding last page
  - Questions: What did you try to extract? Did it work? What went wrong? Would you recommend this?
- [ ] TestFlight release notes — write meaningful notes with each build
- [ ] Beta tester communication channel — consider a simple Discord server or group chat for power testers

## Beta Cadence

| Week | Focus |
|------|-------|
| 1 | Recruit first 20 testers, monitor crash-free rate, fix critical issues |
| 2 | Expand to 50 testers, gather extraction success/failure patterns |
| 3 | Address top feedback themes, push updated build, recruit to 100 |
| 4 | Stabilization, measure final metrics, identify power testers for launch day support |

## Success Metrics (Gate to Public Launch)

| Metric | Target |
|--------|--------|
| Extraction success rate | > 90% |
| Share Extension reliability | > 95% |
| Crash-free rate | > 98% |
| Weekly active testers | 20+ for 2 consecutive weeks |
| Calendar add rate (events actually added) | > 50% |
| Qualitative: "would you recommend this?" | Majority yes |

## Power Tester Program
Identify 5-10 testers who are most active and engaged. These become:
- Early advocates on launch day (Product Hunt upvotes, App Store reviews)
- Sources of testimonial quotes for press kit
- Ongoing feedback channel for post-launch iterations

Criteria for power testers:
- Use the app at least 3x/week
- Submit feedback or bug reports
- Respond to questions about their experience
