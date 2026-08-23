## The seam between the game and the native Firebase SDKs.
##
## Everything Firebase-shaped goes through here, for two reasons. The game runs
## on desktop during development, where no SDK exists at all, and it has to
## keep running — an experiment that only works on a phone cannot be tested.
## And the native plugins are a build-time dependency the editor knows nothing
## about, so the code has to cope with them being absent without pretending
## they are present.
##
## The native side is reached as an Engine singleton, registered by the iOS and
## Android plugins. The contract each has to satisfy is small:
##
##   FirebaseAnalytics
##     log_event(name: String, params: Dictionary) -> void
##     set_user_property(name: String, value: String) -> void
##
##   FirebaseRemoteConfig
##     fetch(minimum_interval_seconds: int) -> void
##     get_string(key: String, fallback: String) -> String
##     signal fetched(success: bool)
##
## Nothing else about Firebase is assumed. In particular the game never asks
## for an installation ID: Remote Config buckets users by it natively, which is
## what keeps a player in the same experiment group between sessions, and
## reading it here would only invite a second, disagreeing source of truth.
class_name FirebaseBridge
extends RefCounted

const ANALYTICS := "FirebaseAnalytics"
const REMOTE_CONFIG := "FirebaseRemoteConfig"


## The native analytics singleton, or null when this build has no SDK.
static func analytics() -> Object:
	return _singleton(ANALYTICS)


## The native Remote Config singleton, or null when this build has no SDK.
static func remote_config() -> Object:
	return _singleton(REMOTE_CONFIG)


## True when the SDKs are actually present. Worth checking before reporting
## anything to the player or the log, so a desktop run does not claim to be
## sending analytics it has no way to send.
static func is_live() -> bool:
	return analytics() != null


static func _singleton(name: String) -> Object:
	if not Engine.has_singleton(name):
		return null
	return Engine.get_singleton(name)
