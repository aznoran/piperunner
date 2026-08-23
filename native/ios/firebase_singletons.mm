// Godot iOS plugin: the two Firebase singletons the game talks to.
//
// Deliberately thin. Everything about *when* to log and *what* a variant means
// lives in GDScript, where it can be read and changed without a native build;
// this file only carries values across the boundary.

#import "firebase_singletons.h"

#import <FirebaseCore/FirebaseCore.h>
#import <FirebaseAnalytics/FirebaseAnalytics.h>
#import <FirebaseRemoteConfig/FirebaseRemoteConfig.h>

// --- helpers ------------------------------------------------------------

static NSString *to_ns(const String &value) {
	return [NSString stringWithUTF8String:value.utf8().get_data()];
}

// Firebase takes NSNumber for numbers and NSString for text, and rejects an
// event outright if a value is of any other class — so anything unexpected is
// stringified rather than dropped, which keeps a mistyped parameter from
// costing the whole event.
static NSDictionary *to_ns_params(const Dictionary &params) {
	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	Array keys = params.keys();
	for (int i = 0; i < keys.size(); i++) {
		String key = keys[i];
		Variant value = params[keys[i]];
		id boxed = nil;
		switch (value.get_type()) {
			case Variant::BOOL:
				boxed = [NSNumber numberWithBool:(bool)value];
				break;
			case Variant::INT:
				boxed = [NSNumber numberWithLongLong:(int64_t)value];
				break;
			case Variant::FLOAT:
				boxed = [NSNumber numberWithDouble:(double)value];
				break;
			default:
				boxed = to_ns(String(value));
				break;
		}
		[out setObject:boxed forKey:to_ns(key)];
	}
	return out;
}

// --- analytics ----------------------------------------------------------

FirebaseAnalyticsPlugin *FirebaseAnalyticsPlugin::instance = NULL;

void FirebaseAnalyticsPlugin::_bind_methods() {
	ClassDB::bind_method(D_METHOD("log_event", "name", "params"),
			&FirebaseAnalyticsPlugin::log_event);
	ClassDB::bind_method(D_METHOD("set_user_property", "name", "value"),
			&FirebaseAnalyticsPlugin::set_user_property);
}

void FirebaseAnalyticsPlugin::log_event(const String &name,
		const Dictionary &params) {
	[FIRAnalytics logEventWithName:to_ns(name) parameters:to_ns_params(params)];
}

void FirebaseAnalyticsPlugin::set_user_property(const String &name,
		const String &value) {
	[FIRAnalytics setUserPropertyString:to_ns(value) forName:to_ns(name)];
}

FirebaseAnalyticsPlugin *FirebaseAnalyticsPlugin::get_singleton() {
	return instance;
}

FirebaseAnalyticsPlugin::FirebaseAnalyticsPlugin() {
	ERR_FAIL_COND(instance != NULL);
	instance = this;
	// Safe to call more than once across the two singletons: FIRApp ignores a
	// second configure, and neither plugin can assume it loaded first.
	if ([FIRApp defaultApp] == nil) {
		[FIRApp configure];
	}
}

FirebaseAnalyticsPlugin::~FirebaseAnalyticsPlugin() {
	if (instance == this) {
		instance = NULL;
	}
}

// --- remote config ------------------------------------------------------

FirebaseRemoteConfigPlugin *FirebaseRemoteConfigPlugin::instance = NULL;

void FirebaseRemoteConfigPlugin::_bind_methods() {
	ClassDB::bind_method(D_METHOD("fetch", "minimum_interval_seconds"),
			&FirebaseRemoteConfigPlugin::fetch);
	ClassDB::bind_method(D_METHOD("get_string", "key", "fallback"),
			&FirebaseRemoteConfigPlugin::get_string);
	ADD_SIGNAL(MethodInfo("fetched",
			PropertyInfo(Variant::BOOL, "success")));
}

void FirebaseRemoteConfigPlugin::fetch(int minimum_interval_seconds) {
	FIRRemoteConfig *config = [FIRRemoteConfig remoteConfig];
	[config fetchWithExpirationDuration:(NSTimeInterval)minimum_interval_seconds
		completionHandler:^(FIRRemoteConfigFetchStatus status, NSError *error) {
			// Activate before answering: the game reads the value straight off
			// the signal, and an un-activated fetch would still be serving the
			// previous session's config.
			[config activateWithCompletion:^(BOOL changed, NSError *activateError) {
				bool ok = (status == FIRRemoteConfigFetchStatusSuccess);
				// Back to the main thread — Godot's signal machinery is not
				// safe to touch from Firebase's completion queue.
				dispatch_async(dispatch_get_main_queue(), ^{
					if (instance != NULL) {
						instance->emit_signal("fetched", ok);
					}
				});
			}];
		}];
}

String FirebaseRemoteConfigPlugin::get_string(const String &key,
		const String &fallback) {
	FIRRemoteConfigValue *value = [[FIRRemoteConfig remoteConfig]
			configValueForKey:to_ns(key)];
	NSString *text = value.stringValue;
	if (text == nil || text.length == 0) {
		return fallback;
	}
	return String::utf8([text UTF8String]);
}

FirebaseRemoteConfigPlugin *FirebaseRemoteConfigPlugin::get_singleton() {
	return instance;
}

FirebaseRemoteConfigPlugin::FirebaseRemoteConfigPlugin() {
	ERR_FAIL_COND(instance != NULL);
	instance = this;
	if ([FIRApp defaultApp] == nil) {
		[FIRApp configure];
	}
}

FirebaseRemoteConfigPlugin::~FirebaseRemoteConfigPlugin() {
	if (instance == this) {
		instance = NULL;
	}
}
