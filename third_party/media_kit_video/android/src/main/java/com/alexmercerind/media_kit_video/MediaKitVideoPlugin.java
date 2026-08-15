/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_video;

import android.content.Context;

import androidx.annotation.NonNull;

import java.util.HashMap;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

/**
 * MediaKitVideoPlugin
 */
public class MediaKitVideoPlugin implements FlutterPlugin, MethodCallHandler {
    private MethodChannel channel;
    private VideoOutputManager videoOutputManager;
    private Context applicationContext;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        applicationContext = flutterPluginBinding.getApplicationContext();
        channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "com.alexmercerind/media_kit_video");
        channel.setMethodCallHandler(this);

        videoOutputManager = new VideoOutputManager(
            applicationContext,
            flutterPluginBinding.getTextureRegistry()
        );

    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        switch (call.method) {
            case "VideoOutputManager.Create": {
                final long handle = Long.parseLong(call.argument("handle"));
                final Boolean forceSurfaceTexture = call.hasArgument("forceSurfaceTexture")
                    ? call.argument("forceSurfaceTexture")
                    : null;
                final boolean attachSurfaceAfterVideoParameters =
                    call.hasArgument("attachSurfaceAfterVideoParameters") &&
                    Boolean.TRUE.equals(call.argument("attachSurfaceAfterVideoParameters"));
                videoOutputManager.create(handle, (id, wid, width, height) -> channel.invokeMethod("VideoOutput.Resize", new HashMap<String, Object>() {{
                    put("handle", handle);
                    put("id", id);
                    put("wid", wid);
                    put("rect", new HashMap<String, Object>() {{
                        put("left", 0);
                        put("top", 0);
                        put("width", width);
                        put("height", height);
                    }});
                }}), forceSurfaceTexture, attachSurfaceAfterVideoParameters);
                result.success(null);
                break;
            }
            case "VideoOutputManager.SetSurfaceSize": {
                final long handle = Long.parseLong(call.argument("handle"));
                final int width = Integer.parseInt(call.argument("width"));
                final int height = Integer.parseInt(call.argument("height"));
                videoOutputManager.setSurfaceSize(handle, width, height);
                result.success(null);
                break;
            }
            case "VideoOutputManager.GetState": {
                final long handle = Long.parseLong(call.argument("handle"));
                result.success(videoOutputManager.getState(handle));
                break;
            }
            case "VideoOutputManager.Dispose": {
                final long handle = Long.parseLong(call.argument("handle"));
                videoOutputManager.dispose(handle);
                result.success(null);
                break;
            }
            case "Utils.IsEmulator": {
                result.success(Utils.isEmulator());
                break;
            }
            default: {
                result.notImplemented();
                break;
            }
        }
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
    }
}
