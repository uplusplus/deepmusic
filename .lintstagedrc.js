module.exports = {
  // Server: ESLint + TypeScript
  'server/src/**/*.ts': [
    'cd server && npx eslint --fix',
    'cd server && npx tsc --noEmit --skipLibCheck',
  ],

  // Mobile: Dart format + analyze
  'mobile/lib/**/*.dart': [
    'cd mobile && dart format --set-exit-if-changed',
    'cd mobile && flutter analyze --no-fatal-infos',
  ],
};
