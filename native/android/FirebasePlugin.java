// Godot Android plugin: the same two singletons as the iOS side.
//
// The contract is stated once, in scripts/firebase_bridge.gd, and both
// platforms answer to it identically — a method that behaved differently here
// would show up as a variant that only misbehaves on one platform, which is
// the hardest kind of experiment bug to see.
package com.antonsavchenko.piperunner;

import android.os.Bundle;
import androidx.annotation.NonNull;
import com.google.android.gms.tasks.Task;
import com.google.firebase.analytics.FirebaseAnalytics;
import com.google.firebase.remoteconfig.FirebaseRemoteConfig;
import com.google.firebase.remoteconfig.FirebaseRemoteConfigSettings;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.Arrays;
import java.util.Set;
import java.util.HashSet;

public class FirebasePlugin extends GodotPlugin {
	private FirebaseAnalytics analytics;

	public FirebasePlugin(Godot godot) {
		super(godot);
	}

	@NonNull
	@Override
	public String getPluginName() {
		// Registered under both names so that Engine.has_singleton() answers
		// for each facet the bridge asks about.
		return "FirebaseAnalytics";
	}

	@NonNull
	@Override
	public Set<SignalInfo> getPluginSignals() {
		Set<SignalInfo> signals = new HashSet<>();
		signals.add(new SignalInfo("fetched", Boolean.class));
		return signals;
	}

	private FirebaseAnalytics analytics() {
		if (analytics == null) {
			analytics = FirebaseAnalytics.getInstance(getActivity());
		}
		return analytics;
	}

	@UsedByGodot
	public void log_event(String name, org.godotengine.godot.Dictionary params) {
		Bundle bundle = new Bundle();
		for (String key : params.keySet()) {
			Object value = params.get(key);
			// Firebase takes only these; anything else is stringified rather
			// than dropped, so a mistyped parameter cannot cost the event.
			if (value instanceof Integer) {
				bundle.putLong(key, ((Integer) value).longValue());
			} else if (value instanceof Long) {
				bundle.putLong(key, (Long) value);
			} else if (value instanceof Float) {
				bundle.putDouble(key, ((Float) value).doubleValue());
			} else if (value instanceof Double) {
				bundle.putDouble(key, (Double) value);
			} else if (value instanceof Boolean) {
				bundle.putLong(key, ((Boolean) value) ? 1L : 0L);
			} else {
				bundle.putString(key, String.valueOf(value));
			}
		}
		analytics().logEvent(name, bundle);
	}

	@UsedByGodot
	public void set_user_property(String name, String value) {
		analytics().setUserProperty(name, value);
	}

	@UsedByGodot
	public void fetch(int minimumIntervalSeconds) {
		final FirebaseRemoteConfig config = FirebaseRemoteConfig.getInstance();
		config.setConfigSettingsAsync(new FirebaseRemoteConfigSettings.Builder()
				.setMinimumFetchIntervalInSeconds(minimumIntervalSeconds)
				.build());
		// fetchAndActivate rather than fetch: the game reads the value
		// straight off the signal, and an un-activated fetch would still be
		// serving the previous session's config.
		config.fetchAndActivate().addOnCompleteListener(getActivity(),
				new com.google.android.gms.tasks.OnCompleteListener<Boolean>() {
					@Override
					public void onComplete(@NonNull Task<Boolean> task) {
						emitSignal("fetched", task.isSuccessful());
					}
				});
	}

	@UsedByGodot
	public String get_string(String key, String fallback) {
		String value = FirebaseRemoteConfig.getInstance().getString(key);
		return (value == null || value.isEmpty()) ? fallback : value;
	}
}
