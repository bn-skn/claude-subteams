---
name: mobile-development
description: Use when building, architecting, or deploying mobile applications with React Native, Flutter, or native platforms
---

# Mobile Development

## Overview

Mobile apps have unique constraints: limited resources, platform-specific APIs, app store review processes, and diverse device fragmentation. A structured approach prevents platform-specific pitfalls.

**Core principle:** ALWAYS consider both platforms (iOS and Android) for every feature decision. NEVER ship untested on either platform.

## When to Use

- Starting a new mobile project or feature
- Choosing between React Native, Flutter, or native development
- Implementing navigation, state management, or deep linking
- Working with platform APIs and permissions
- Setting up mobile testing or app store deployment

## Framework Selection

### Decision Checklist
1. **React Native** -- Choose when team knows JavaScript/TypeScript, needs code sharing with web, or requires native module access
2. **Flutter** -- Choose when targeting pixel-perfect UI across platforms, need custom rendering, or team knows Dart
3. **Native (Swift/Kotlin)** -- Choose when performance is critical, need deep platform integration, or building platform-specific features
4. NEVER choose a framework based on hype; choose based on team skills and project requirements
5. ALWAYS prototype the riskiest feature in the chosen framework before committing

## Mobile Architecture

### Navigation
1. Use a navigation library appropriate to your framework (React Navigation, GoRouter, NavigationStack)
2. Define all routes in a central configuration
3. Handle deep links at the navigation layer, not in individual screens
4. MUST handle back button behavior correctly on Android
5. ALWAYS preserve navigation state across app restarts when appropriate

### State Management
1. Choose one state management approach and use it consistently
2. Separate UI state (loading, modals) from domain state (user data, settings)
3. Persist critical state to survive app kills (AsyncStorage, SharedPreferences)
4. NEVER store sensitive data in plain-text local storage
5. ALWAYS handle the "cold start with stale state" scenario

### Deep Linking
1. Register URL schemes and universal/app links for both platforms
2. Parse deep link parameters at a single entry point
3. Handle deep links when app is cold-started, backgrounded, and foregrounded
4. MUST validate deep link parameters before navigation
5. ALWAYS provide fallback behavior for malformed deep links

## Platform APIs and Permissions

### Permission Handling Checklist
1. Request permissions at the moment they are needed, not at app launch
2. Explain to the user WHY the permission is needed before requesting
3. Handle all three states: granted, denied, never-asked
4. MUST handle "permanently denied" by directing user to system settings
5. NEVER block the entire app if a non-critical permission is denied
6. Test permission flows on both platforms -- behavior differs significantly

### Common Platform APIs
| Feature | iOS | Android |
|---------|-----|---------|
| Push notifications | APNs | FCM |
| Background tasks | BGTaskScheduler | WorkManager |
| Local storage | Keychain (secure), UserDefaults | Keystore (secure), SharedPreferences |
| Camera/Photos | AVFoundation, PhotoKit | CameraX, MediaStore |
| Location | CoreLocation | FusedLocationProvider |

## Mobile Testing

### Testing Strategy
1. **Unit tests** -- Business logic, state management, data transformations
2. **Widget/Component tests** -- Individual UI component rendering and interaction
3. **Integration tests** -- User flows across multiple screens
4. **E2E tests** -- Full app testing on real devices or emulators

### Framework-Specific Tools
| Framework | Unit | E2E |
|-----------|------|-----|
| React Native | Jest | Detox, Maestro |
| Flutter | flutter_test | integration_test, Maestro |
| iOS Native | XCTest | XCUITest |
| Android Native | JUnit | Espresso |

### Testing Checklist
1. Run tests on both platforms in CI
2. Test on minimum supported OS versions
3. Test on different screen sizes (phone, tablet)
4. MUST test offline behavior
5. MUST test permission denial flows
6. NEVER skip testing on the less-popular platform

## App Store Deployment

### Pre-Submission Checklist
1. Increment version number and build number
2. Generate signed release build (code signing configured in CI)
3. Run full test suite against release build
4. Test on physical devices, not just simulators
5. Verify all required metadata: screenshots, descriptions, privacy policy
6. MUST comply with platform guidelines (App Store Review Guidelines, Google Play policies)

### Deployment Pipeline
```
feature branch
  -> PR with tests passing on both platforms
    -> merge to main
      -> CI builds signed release
        -> deploy to TestFlight / Internal Testing
          -> QA approval
            -> submit to App Store / Play Store
```

### Post-Submission Checklist
1. Monitor crash reports after release (Crashlytics, Sentry)
2. Track app store review status
3. MUST have rollback plan (staged rollout percentage)
4. Respond to app store rejection feedback within 24 hours

## Critical Rules

- NEVER ship without testing on both iOS and Android
- NEVER store tokens or secrets in client-side code
- ALWAYS handle network failures gracefully (offline mode)
- MUST test on physical devices before release
- MUST support at least 2 major OS versions back
- NEVER ignore app store guideline changes

## Quick Reference

| Phase | Key Activities | Deliverable |
|-------|---------------|-------------|
| Architecture | Framework choice, navigation, state | Architecture doc |
| Development | Features, platform APIs, permissions | Working builds |
| Testing | Unit, integration, E2E on both platforms | Test reports |
| Deployment | Signing, store submission, monitoring | Published app |
