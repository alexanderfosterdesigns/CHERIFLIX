/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_video;

import android.graphics.SurfaceTexture;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.view.Surface;

import java.lang.reflect.Method;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Locale;
import java.util.Objects;

import io.flutter.view.TextureRegistry;

public class VideoOutput implements TextureRegistry.SurfaceProducer.Callback {
    private static final String TAG = "VideoOutput";
    private static final Method newGlobalObjectRef;
    private static final Method deleteGlobalObjectRef;
    private static final HashSet<Long> deletedGlobalObjectRefs = new HashSet<>();
    private static final Handler handler = new Handler(Looper.getMainLooper());

    static {
        try {
            // com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper is part of package:media_kit_libs_android_video & package:media_kit_libs_android_audio packages.
            // Use reflection to invoke methods of com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper.
            Class<?> mediaKitAndroidHelperClass = Class.forName("com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper");
            newGlobalObjectRef = mediaKitAndroidHelperClass.getDeclaredMethod("newGlobalObjectRef", Object.class);
            deleteGlobalObjectRef = mediaKitAndroidHelperClass.getDeclaredMethod("deleteGlobalObjectRef", long.class);
            newGlobalObjectRef.setAccessible(true);
            deleteGlobalObjectRef.setAccessible(true);
        } catch (Throwable e) {
            Log.i("media_kit", "package:media_kit_libs_android_video missing. Make sure you have added it to pubspec.yaml.");
            throw new RuntimeException("Failed to initialize com.alexmercerind.media_kit_video.VideoOutput.");
        }
    }

    private long id = 0;
    private long wid = 0;
    private int width = 1;
    private int height = 1;

    private final TextureUpdateCallback textureUpdateCallback;

    private final boolean useSurfaceTexture;
    private final boolean attachSurfaceAfterVideoParameters;
    private final TextureRegistry.SurfaceProducer surfaceProducer;
    private final TextureRegistry.SurfaceTextureEntry surfaceTextureEntry;
    private Surface surface;
    private boolean hasExplicitSurfaceSize;
    private int surfaceAttachRetryCount = 0;
    private int frameAvailableCount = 0;
    private long lastFrameAvailableAtMs = 0;
    private int frameWatchdogGeneration = 0;
    private int frameWatchdogReattachCount = 0;

    private final Object lock = new Object();

    VideoOutput(
        TextureRegistry textureRegistryReference,
        TextureUpdateCallback textureUpdateCallback,
        boolean useSurfaceTexture,
        boolean attachSurfaceAfterVideoParameters
    ) {
        this.textureUpdateCallback = textureUpdateCallback;
        this.useSurfaceTexture = useSurfaceTexture;
        this.attachSurfaceAfterVideoParameters = attachSurfaceAfterVideoParameters;
        this.hasExplicitSurfaceSize = !useSurfaceTexture || !attachSurfaceAfterVideoParameters;

        if (useSurfaceTexture) {
            surfaceProducer = null;
            surfaceTextureEntry = textureRegistryReference.createSurfaceTexture();
            final SurfaceTexture surfaceTexture = surfaceTextureEntry.surfaceTexture();
            surfaceTexture.setOnFrameAvailableListener(
                (ignored) -> {
                    synchronized (lock) {
                        frameAvailableCount += 1;
                        lastFrameAvailableAtMs = SystemClock.elapsedRealtime();
                        // Invalidate stale watchdog tasks once real frames arrive.
                        frameWatchdogGeneration += 1;
                    }
                },
                handler
            );
            surfaceTexture.setDefaultBufferSize(width, height);
            if (!attachSurfaceAfterVideoParameters) {
                surface = new Surface(surfaceTexture);
                // Ensure initial surface attachment is not dependent on a later
                // size change call when eager attach mode is requested.
                onSurfaceAvailable();
                Log.i(TAG, "Using SurfaceTexture-backed video output.");
            } else {
                Log.i(TAG, "Using SurfaceTexture-backed video output with deferred surface attachment.");
            }
        } else {
            surfaceTextureEntry = null;
            surfaceProducer = textureRegistryReference.createSurfaceProducer();
            surfaceProducer.setCallback(this);
            Log.i(TAG, "Using SurfaceProducer-backed video output.");
        }
    }

    public void dispose() {
        synchronized (lock) {
            try {
                if (surface != null) {
                    surface.release();
                    surface = null;
                } else if (surfaceProducer != null) {
                    surfaceProducer.getSurface().release();
                }
            } catch (Throwable e) {
                Log.e(TAG, "dispose", e);
            }
            try {
                if (surfaceProducer != null) {
                    surfaceProducer.release();
                }
                if (surfaceTextureEntry != null) {
                    try {
                        surfaceTextureEntry.surfaceTexture().setOnFrameAvailableListener(null);
                    } catch (Throwable e) {
                        Log.e(TAG, "dispose.clearOnFrameAvailableListener", e);
                    }
                    surfaceTextureEntry.release();
                }
            } catch (Throwable e) {
                Log.e(TAG, "dispose", e);
            }
            surfaceAttachRetryCount = 0;
            frameWatchdogReattachCount = 0;
            frameWatchdogGeneration += 1;
            onSurfaceCleanup();
        }
    }

    public void setSurfaceSize(int width, int height) {
        setSurfaceSize(width, height, false);
    }

    private void setSurfaceSize(int width, int height, boolean force) {
        synchronized (lock) {
            try {
                // A first 1x1 size prime is used to force early attachment.
                // Do not skip when surface isn't attached yet.
                final boolean hasAttachedSurface = id != 0 && wid != 0;
                if (
                    !force &&
                    this.width == width &&
                    this.height == height &&
                    hasAttachedSurface
                ) {
                    return;
                }
                this.width = width;
                this.height = height;
                if (surfaceTextureEntry != null && attachSurfaceAfterVideoParameters) {
                    hasExplicitSurfaceSize = true;
                }
                if (surfaceProducer != null) {
                    surfaceProducer.setSize(width, height);
                }
                if (surfaceTextureEntry != null) {
                    final SurfaceTexture surfaceTexture = surfaceTextureEntry.surfaceTexture();
                    surfaceTexture.setDefaultBufferSize(width, height);
                }
                onSurfaceAvailable();
            } catch (Throwable e) {
                Log.e(TAG, "setSurfaceSize", e);
            }
        }
    }

    @Override
    public void onSurfaceAvailable() {
        synchronized (lock) {
            Log.i(TAG, "onSurfaceAvailable");
            if (
                surfaceTextureEntry != null &&
                attachSurfaceAfterVideoParameters &&
                !hasExplicitSurfaceSize
            ) {
                Log.i(TAG, "Deferring SurfaceTexture attachment until the first explicit surface size.");
                return;
            }
            if (surfaceTextureEntry != null) {
                id = surfaceTextureEntry.id();
                if (surface == null) {
                    surface = new Surface(surfaceTextureEntry.surfaceTexture());
                }
                if (wid == 0) {
                    wid = newGlobalObjectRef(surface);
                }
            } else if (surfaceProducer != null) {
                id = surfaceProducer.id();
                wid = newGlobalObjectRef(surfaceProducer.getSurface());
            }
            if (wid != 0) {
                surfaceAttachRetryCount = 0;
                frameWatchdogReattachCount = 0;
            } else {
                Log.w(TAG, "Surface attachment completed without a usable wid.");
            }
            textureUpdateCallback.onTextureUpdate(id, wid, width, height);
        }
    }

    @Override
    public void onSurfaceCleanup() {
        synchronized (lock) {
            Log.i(TAG, "onSurfaceCleanup");
            textureUpdateCallback.onTextureUpdate(id, 0, width, height);
            surfaceAttachRetryCount = 0;
            frameWatchdogReattachCount = 0;
            frameWatchdogGeneration += 1;
            if (wid != 0) {
                final long widReference = wid;
                wid = 0;
                handler.postDelayed(() -> deleteGlobalObjectRef(widReference), 5000);
            }
        }
    }

    public HashMap<String, Object> snapshotState() {
        synchronized (lock) {
            final HashMap<String, Object> state = new HashMap<>();
            state.put("id", id);
            state.put("wid", wid);
            state.put("width", width);
            state.put("height", height);
            state.put("useSurfaceTexture", useSurfaceTexture);
            state.put("surfaceAttachRetryCount", surfaceAttachRetryCount);
            state.put("frameAvailableCount", frameAvailableCount);
            state.put("lastFrameAvailableAtMs", lastFrameAvailableAtMs);
            state.put("frameWatchdogReattachCount", frameWatchdogReattachCount);
            return state;
        }
    }

    private static long newGlobalObjectRef(Object object) {
        Log.i(TAG, String.format(Locale.ENGLISH, "newGlobalRef: object = %s", object));
        try {
            return (long) Objects.requireNonNull(newGlobalObjectRef.invoke(null, object));
        } catch (Throwable e) {
            Log.e(TAG, "newGlobalRef", e);
            return 0;
        }
    }

    private static void deleteGlobalObjectRef(long ref) {
        if (deletedGlobalObjectRefs.contains(ref)) {
            Log.i(TAG, String.format(Locale.ENGLISH, "deleteGlobalObjectRef: ref = %d ALREADY DELETED", ref));
            return;
        }
        if (deletedGlobalObjectRefs.size() > 100) {
            deletedGlobalObjectRefs.clear();
        }
        deletedGlobalObjectRefs.add(ref);
        Log.i(TAG, String.format(Locale.ENGLISH, "deleteGlobalObjectRef: ref = %d", ref));
        try {
            deleteGlobalObjectRef.invoke(null, ref);
        } catch (Throwable e) {
            Log.e(TAG, "deleteGlobalObjectRef", e);
        }
    }
}
