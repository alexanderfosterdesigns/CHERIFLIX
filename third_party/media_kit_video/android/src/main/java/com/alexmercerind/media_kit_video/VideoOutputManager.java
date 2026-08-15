/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_video;

import android.app.UiModeManager;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.content.res.Configuration;
import android.util.Log;

import java.util.HashMap;
import java.util.Locale;
import java.util.Objects;

import io.flutter.view.TextureRegistry;

public class VideoOutputManager {
    private static final String TAG = "VideoOutputManager";
    private static final String FORCE_SURFACE_TEXTURE_SYSTEM_PROPERTY =
        "media_kit_video.force_surface_texture";
    private static final String FORCE_SURFACE_TEXTURE_SYSTEM_PROPERTY_CHERIFLIX =
        "cheriflix.media_kit_video.force_surface_texture";
    private static final String FORCE_SURFACE_TEXTURE_MANIFEST_KEY =
        "com.alexmercerind.media_kit_video.force_surface_texture";

    private final HashMap<Long, VideoOutput> videoOutputs = new HashMap<>();
    private final TextureRegistry textureRegistryReference;
    private final Object lock = new Object();
    private final boolean forceSurfaceTexture;

    VideoOutputManager(Context applicationContext, TextureRegistry textureRegistryReference) {
        this.textureRegistryReference = textureRegistryReference;
        this.forceSurfaceTexture = shouldForceSurfaceTexture(applicationContext);
    }

    public void create(
        long handle,
        TextureUpdateCallback textureUpdateCallback,
        Boolean forceSurfaceTextureOverride,
        boolean attachSurfaceAfterVideoParameters
    ) {
        synchronized (lock) {
            Log.i(TAG, String.format(Locale.ENGLISH, "com.alexmercerind.media_kit_video.VideoOutputManager.create: %d", handle));
            if (!videoOutputs.containsKey(handle)) {
                final boolean useSurfaceTexture = forceSurfaceTextureOverride != null
                    ? forceSurfaceTextureOverride
                    : forceSurfaceTexture;
                final VideoOutput videoOutput = new VideoOutput(
                    textureRegistryReference,
                    textureUpdateCallback,
                    useSurfaceTexture,
                    attachSurfaceAfterVideoParameters
                );
                videoOutputs.put(handle, videoOutput);
            }
        }
    }

    public void dispose(long handle) {
        synchronized (lock) {
            Log.i(TAG, String.format(Locale.ENGLISH, "com.alexmercerind.media_kit_video.VideoOutputManager.dispose: %d", handle));
            if (videoOutputs.containsKey(handle)) {
                Objects.requireNonNull(videoOutputs.get(handle)).dispose();
                videoOutputs.remove(handle);
            }
        }
    }

    public void setSurfaceSize(long handle, int width, int height) {
        synchronized (lock) {
            Log.i(TAG, String.format(Locale.ENGLISH, "com.alexmercerind.media_kit_video.VideoOutputManager.setSurfaceSize: %d %d %d", handle, width, height));
            if (videoOutputs.containsKey(handle)) {
                Objects.requireNonNull(videoOutputs.get(handle)).setSurfaceSize(width, height);
            }
        }
    }

    public HashMap<String, Object> getState(long handle) {
        synchronized (lock) {
            if (!videoOutputs.containsKey(handle)) {
                return null;
            }
            return Objects.requireNonNull(videoOutputs.get(handle)).snapshotState();
        }
    }

    private static boolean shouldForceSurfaceTexture(Context context) {
        final Boolean runtimeOverride = readRuntimeOverride();
        if (runtimeOverride != null) {
            Log.i(TAG, "Using runtime surface texture override: " + runtimeOverride);
            return runtimeOverride;
        }
        final Boolean manifestOverride = readManifestOverride(context);
        if (manifestOverride != null) {
            Log.i(TAG, "Using manifest surface texture override: " + manifestOverride);
            return manifestOverride;
        }
        try {
            final UiModeManager uiModeManager =
                (UiModeManager) context.getSystemService(Context.UI_MODE_SERVICE);
            if (uiModeManager == null) {
                return false;
            }
            return uiModeManager.getCurrentModeType() == Configuration.UI_MODE_TYPE_TELEVISION;
        } catch (Throwable throwable) {
            Log.w(TAG, "Failed to detect television UI mode.", throwable);
            return false;
        }
    }

    private static Boolean readRuntimeOverride() {
        final String primary = System.getProperty(FORCE_SURFACE_TEXTURE_SYSTEM_PROPERTY);
        final Boolean primaryValue = parseBooleanOverride(primary);
        if (primaryValue != null) {
            return primaryValue;
        }
        final String cheriflix = System.getProperty(FORCE_SURFACE_TEXTURE_SYSTEM_PROPERTY_CHERIFLIX);
        return parseBooleanOverride(cheriflix);
    }

    private static Boolean readManifestOverride(Context context) {
        try {
            final PackageManager packageManager = context.getPackageManager();
            if (packageManager == null) {
                return null;
            }
            final ApplicationInfo applicationInfo = packageManager.getApplicationInfo(
                context.getPackageName(),
                PackageManager.GET_META_DATA
            );
            if (applicationInfo == null || applicationInfo.metaData == null) {
                return null;
            }
            if (!applicationInfo.metaData.containsKey(FORCE_SURFACE_TEXTURE_MANIFEST_KEY)) {
                return null;
            }
            final Object raw = applicationInfo.metaData.get(FORCE_SURFACE_TEXTURE_MANIFEST_KEY);
            if (raw instanceof Boolean) {
                return (Boolean) raw;
            }
            if (raw instanceof String) {
                return parseBooleanOverride((String) raw);
            }
            if (raw instanceof Integer) {
                return ((Integer) raw) != 0;
            }
            return null;
        } catch (Throwable throwable) {
            Log.w(TAG, "Failed to read surface texture manifest override.", throwable);
            return null;
        }
    }

    private static Boolean parseBooleanOverride(String value) {
        if (value == null) {
            return null;
        }
        final String normalized = value.trim().toLowerCase(Locale.ENGLISH);
        if (normalized.isEmpty()) {
            return null;
        }
        if (
            normalized.equals("1") ||
            normalized.equals("true") ||
            normalized.equals("yes") ||
            normalized.equals("on")
        ) {
            return true;
        }
        if (
            normalized.equals("0") ||
            normalized.equals("false") ||
            normalized.equals("no") ||
            normalized.equals("off")
        ) {
            return false;
        }
        return null;
    }
}
