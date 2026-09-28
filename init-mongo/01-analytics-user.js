// Creates analytics_user on activity_db — the Mongo counterpart of
// init-db/01-init.sh.
//
// Mongo runs everything in /docker-entrypoint-initdb.d exactly once, when the
// data directory is empty, as the root user. The password comes from
// ANALYTICS_DB_PASSWORD in devboard-infra/.env, which must match the password
// inside MONGO_URI in devboard-analytics/.env.
//
// Like 01-init.sh this does NOT run against an existing volume. setup.bat keeps
// its own create-user logic as the path for already-initialised installs.

const password = process.env.ANALYTICS_DB_PASSWORD;

if (!password) {
  print('  SKIP  analytics_user — no ANALYTICS_DB_PASSWORD (check devboard-infra/.env)');
} else {
  const activityDb = db.getSiblingDB('activity_db');
  if (activityDb.getUser('analytics_user') === null) {
    activityDb.createUser({
      user: 'analytics_user',
      pwd: password,
      roles: [{ role: 'readWrite', db: 'activity_db' }],
    });
  }
  print('  ok    analytics_user / activity_db');
}
