# Monetization Strategy

## Current State
- Free tier: 20 extractions per device per day
- No paid tier implemented
- API cost per extraction: ~$0.002-0.005 (GPT-5 nano with web search)
- No user accounts (device-only identity)

## Options Analysis

| Model | Pros | Cons | Revenue potential |
|-------|------|------|-------------------|
| **Freemium: lower free tier + paid unlimited** | Natural upgrade trigger, aligns cost with usage | May frustrate casual users | Medium-high |
| **One-time purchase** | Simple, no subscription fatigue, clear value | No recurring revenue, can't adjust pricing | Medium |
| **Subscription** | Recurring revenue, covers ongoing API costs | Subscription fatigue for utility apps | High (if retention) |
| **Free + tip jar** | Goodwill, zero friction | Unpredictable, very low conversion | Low |
| **Ads** | Passive revenue | Degrades UX, privacy contradiction | Low-medium |

## Recommendation

**Hybrid: Lower free tier + annual unlock with lifetime option**

### Free Tier
- **5 extractions per day** (down from 20)
- Rationale: 5/day is enough for casual use (1-2 events per outing). Power users who capture 10+ events at a festival or conference hit the limit and see clear value in upgrading.

### Premium Tier: "Event Snap Pro"
- **$4.99/year** or **$0.99/month**
- **$9.99 lifetime** (one-time purchase alternative)
- Features:
  - Unlimited extractions
  - Priority processing (optional — could route to a faster/better model)
  - Early access to new features

### Why This Structure
1. **Low annual price reduces friction** — $4.99/yr feels like nothing for a tool you use regularly
2. **Lifetime option captures users who hate subscriptions** — common in the iOS indie app space
3. **Covers API costs comfortably** — even at $4.99/yr, a user doing 10 extractions/day costs ~$18/yr in API, so heavy users at the lifetime tier are a loss leader — but most users will do 2-3/day ($3-5/yr cost), well within margin
4. **No ads** — preserves the privacy-first positioning

### Pricing Sensitivity
- At $4.99/yr: expect higher conversion, lower ARPU
- At $9.99/yr: expect lower conversion, higher ARPU
- Start with $4.99/yr, increase if retention proves strong

## Implementation Requirements

### Technical
- [ ] StoreKit 2 integration (auto-renewable subscription + non-consumable lifetime)
- [ ] Receipt validation (server-side via Worker, or on-device with StoreKit 2)
- [ ] Entitlement check in extraction flow (free tier counter vs. premium bypass)
- [ ] Worker-side: device premium status tracking (via JWT claims or separate endpoint)
- [ ] Restore purchases flow
- [ ] Subscription management deep link (Settings -> Manage Subscription)

### UX
- [ ] Upgrade prompt when free tier limit is hit (soft paywall — show extracted event, ask to upgrade to add it)
- [ ] Premium badge or indicator in Settings
- [ ] "Why upgrade?" screen with feature comparison
- [ ] No hard paywall on core functionality — free users always get 5/day

### App Store
- [ ] Subscription description and terms for App Store review
- [ ] Privacy policy update (payment processing via Apple)
- [ ] Subscription management URL

## Revenue Projections (Conservative)

Assuming 5,000 downloads in first 6 months:

| Scenario | Conversion | Paying users | Annual revenue |
|----------|-----------|--------------|----------------|
| Low | 2% | 100 | $500 |
| Medium | 5% | 250 | $1,250 |
| High | 10% | 500 | $2,500 |

These are modest numbers. The goal for v1 is to cover API costs and validate willingness to pay, not to generate significant income.

## When to Implement

**Not at launch.** Launch as free (current 20/day limit) to maximize downloads and reviews. Introduce the paid tier after:
1. 500+ downloads
2. Stable 4.5+ App Store rating
3. Baseline retention data (need to know Day 30 retention before pricing)
4. At least one month of cost data at scale

Estimated timeline: 1-2 months post-launch.
