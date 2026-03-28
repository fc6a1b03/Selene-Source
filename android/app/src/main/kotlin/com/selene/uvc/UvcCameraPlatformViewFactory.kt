package com.selene.uvc

import android.app.Activity
import android.content.Context
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class UvcCameraPlatformViewFactory(
    private val activity: Activity,
    private val channel: MethodChannel,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    var currentView: UvcCameraPlatformView? = null
        private set

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        currentView?.dispose()
        currentView = UvcCameraPlatformView(
            activity = activity,
            context = context,
            channel = channel,
            args = args,
        )
        return currentView as UvcCameraPlatformView
    }

    fun dispose() {
        currentView?.dispose()
        currentView = null
    }
}
