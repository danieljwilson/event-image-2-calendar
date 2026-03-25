# Metrics & Growth

## Key Performance Indicators

| Metric | Month 1 | Month 3 | Month 6 |
|--------|---------|---------|---------|
| Total downloads | 500 | 2,000 | 5,000 |
| Weekly active users | 100 | 400 | 1,000 |
| Extraction success rate | >90% | >93% | >95% |
| Calendar add rate | >60% | >65% | >70% |
| App Store rating | 4.5+ | 4.5+ | 4.5+ |
| Retention (Day 7) | 30% | 35% | 40% |
| Retention (Day 30) | 15% | 20% | 25% |

## Tracking Tools

| What | Tool | Notes |
|------|------|-------|
| Downloads, retention, conversion | App Store Connect analytics | Built-in, free |
| Extraction success/failure | Cloudflare Worker analytics dashboard | Already built (admin dashboard) |
| API costs per extraction | Worker usage tracking | Already built (token counting + pricing) |
| Landing page traffic | Plausible or PostHog | Lightweight, privacy-friendly |
| Social media metrics | Native analytics per platform | Twitter Analytics, TikTok Studio, etc. |
| App Store keyword rankings | AppFollow or AppTweak (free tier) | Optional, useful for ASO iteration |

## Growth Loops

### Organic Virality
- **Share Extension exposure:** When users share events from Event Snap to friends (via calendar invite, message, etc.), recipients discover the app exists
- **"Added with Event Snap" note:** Optional line in calendar event description — toggleable in settings. Low-friction awareness driver
- **Digest email forwarding:** Users forwarding their daily digest to friends includes Event Snap branding
- **Word of mouth:** The "snap a poster" use case is inherently demonstrable — users show friends in person

### Referral Program (Future)
- "Give a friend 30 days premium" (when paid tier exists)
- Tracked via unique referral codes or links
- Implement after establishing baseline conversion metrics

### Seasonal Spikes

| Month | Opportunity | Action |
|-------|-------------|--------|
| January | New Year productivity wave | "Organize your 2027" campaign |
| March-May | Festival announcements (SXSW, Coachella, local festivals) | Festival-themed content + "festival season prep" video |
| June-August | Concert/outdoor event season | Peak usage period — optimize, don't launch new features |
| September | Back to school, campus events | University outreach push, campus ambassador program |
| October-November | Conference season, holiday events | Conference/professional angle content |
| December | Holiday event planning | "Holiday events" keyword push, gift guide submissions |

## Cost Monitoring

Current API cost per extraction (approximate):
- GPT-5 nano: ~$0.002-0.005 per extraction (with web search)
- Free tier: 20/day/device = max ~$0.10/device/day worst case

**Break-even analysis needed:**
- At what user volume do API costs exceed $X/month?
- What's the conversion rate needed to cover costs with paid tier?
- Track via the existing Worker analytics dashboard

## Monthly Review Checklist

- [ ] Check App Store Connect: downloads, conversion rate, retention curves
- [ ] Check Worker dashboard: extraction volume, success rate, cost per extraction
- [ ] Check App Store reviews: respond to all, identify patterns
- [ ] Check social metrics: which content performed best?
- [ ] Update keyword strategy if running Apple Search Ads
- [ ] Evaluate: is the current free tier limit appropriate?
