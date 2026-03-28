package com.selene.uvc

import android.app.Activity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class UvcCameraPlugin(
    private val activity: Activity,
    private val channel: MethodChannel,
    private val viewFactory: UvcCameraPlatformViewFactory,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "selene.uvc_camera/channel"
        const val VIEW_NAME = "selene.uvc_camera/view"

        fun registerWith(
            flutterEngine: FlutterEngine,
            activity: Activity,
        ): UvcCameraPlugin {
            val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            val factory = UvcCameraPlatformViewFactory(activity, channel)
            flutterEngine.platformViewsController.registry.registerViewFactory(VIEW_NAME, factory)

            val plugin = UvcCameraPlugin(activity, channel, factory)
            channel.setMethodCallHandler(plugin)
            return plugin
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val view = viewFactory.currentView
        if (view == null) {
            result.error("NO_VIEW", "UVC 预览视图尚未创建", null)
            return
        }

        when (call.method) {
            "initializeCamera" -> {
                view.initializeCamera()
                result.success(null)
            }

            "openUVCCamera" -> view.openCamera(result)
            "closeCamera" -> view.closeCamera(result)
            "takePicture" -> view.takePicture(result)
            "captureVideo" -> view.captureVideo(result)
            "getAllPreviewSizes" -> result.success(view.getAllPreviewSizes())
            "getCurrentCameraRequestParameters" -> result.success(view.getCurrentCameraRequestParameters())
            "updateResolution" -> {
                view.updateResolution(call.arguments)
                result.success(null)
            }

            "setZoom" -> {
                val zoom = call.argument<Int>("zoom") ?: 0
                view.setZoom(zoom)
                result.success(null)
            }

            "getZoom" -> result.success(view.getZoom())
            "getMaxZoom" -> result.success(view.getMaxZoom())

            "resetZoom" -> {
                view.resetZoom()
                result.success(null)
            }

            "disposePlatformView" -> {
                viewFactory.dispose()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        viewFactory.dispose()
    }
}
