# Into English iOS

- Personal app for the user and their wife. Each uses their own ChatGPT OAuth credentials and plan allowance. Never introduce a shared developer API key or silently change billing.
- Preserve the working OAuth bundle identifier and Keychain service so installed users remain connected.
- Keep the ivory/coral visual language of the original web prototype. Korean UI; English output with Korean explanations.
- Commit completed development changes and push to https://github.com/yoobato/mydy-into-english-ios after appropriate validation. Never commit tokens, user conversations, signing assets, or build output.
- Marketing version starts at 1.0.0. Every actual app build increments the tracked BuildNumber.txt through Scripts/increment-build-number.py. Do not reset it. Simulator builds count too. Verify the installed app's Info.plist build number before reporting it.
- project.yml is the XcodeGen source of truth. Regenerate after changing project configuration.
- Tests must not use a real ChatGPT account or consume the user's allowance. Use synthetic fixtures. Real-device AI verification requires the user’s explicit interaction in the app.
