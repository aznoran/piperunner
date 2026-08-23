// Godot iOS plugin: the two Firebase singletons the game talks to.
//
// The GDScript side is scripts/firebase_bridge.gd, and the contract is stated
// there. Nothing here may widen it without that file changing first — the game
// treats a missing singleton as "no SDK" and keeps playing, so a method that
// exists on one platform and not the other would fail silently rather than
// loudly.
//
// Built against the Godot source tree as an iOS plugin; see docs/experiment.md
// for the build and for what has to be in place before it can be built at all.

#ifndef PIPERUNNER_FIREBASE_SINGLETONS_H
#define PIPERUNNER_FIREBASE_SINGLETONS_H

#include "core/object/class_db.h"
#include "core/object/ref_counted.h"

// Analytics: fire-and-forget. Nothing here reports success, because the SDK
// batches and retries on its own and a caller that waited on it would only be
// waiting on the batch timer.
class FirebaseAnalyticsPlugin : public Object {
	GDCLASS(FirebaseAnalyticsPlugin, Object);

	static FirebaseAnalyticsPlugin *instance;

protected:
	static void _bind_methods();

public:
	void log_event(const String &name, const Dictionary &params);
	void set_user_property(const String &name, const String &value);

	static FirebaseAnalyticsPlugin *get_singleton();

	FirebaseAnalyticsPlugin();
	~FirebaseAnalyticsPlugin();
};

// Remote Config: fetch is asynchronous and answers on the `fetched` signal.
// `get_string` reads the activated cache, so it is only meaningful after a
// fetch has come back — which is why the game waits for the signal rather than
// polling.
class FirebaseRemoteConfigPlugin : public Object {
	GDCLASS(FirebaseRemoteConfigPlugin, Object);

	static FirebaseRemoteConfigPlugin *instance;

protected:
	static void _bind_methods();

public:
	void fetch(int minimum_interval_seconds);
	String get_string(const String &key, const String &fallback);

	static FirebaseRemoteConfigPlugin *get_singleton();

	FirebaseRemoteConfigPlugin();
	~FirebaseRemoteConfigPlugin();
};

#endif // PIPERUNNER_FIREBASE_SINGLETONS_H
