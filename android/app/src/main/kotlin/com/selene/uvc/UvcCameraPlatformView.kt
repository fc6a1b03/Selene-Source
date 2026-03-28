package com.selene.uvc

import android.app.Activity
import android.content.Context
import android.graphics.SurfaceTexture
import android.hardware.usb.UsbDevice
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.TextureView
import android.view.View
import android.widget.FrameLayout
import com.google.gson.Gson
import com.jiangdg.ausbc.MultiCameraClient
import com.jiangdg.ausbc.callback.ICameraStateCallBack
import com.jiangdg.ausbc.callback.ICaptureCallBack
import com.jiangdg.ausbc.callback.IDeviceConnectCallBack
import com.jiangdg.ausbc.utils.Logger
import com.jiangdg.ausbc.utils.SettableFuture
import com.jiangdg.usb.USBMonitor
import com.jiangdg.uvc.IButtonCallback
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import org.moontechlab.selene.BuildConfig
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class UvcCameraPlatformView(
    private val activity: Activity,
    context: Context,
    private val channel: MethodChannel,
    args: Any?,
) : PlatformView, ICameraStateCallBack {

    companion object {
        private const val TAG = "SeleneUvcView"
    }

    private val rootView = FrameLayout(context)
    private val cameraView = TextureView(context)
    private val cameraParams = buildCameraParams(args)

    private var cameraClient: MultiCameraClient? = null
    private var currentCamera: SettableFuture<MultiCameraClient.ICamera>? = null
    private val cameraMap = hashMapOf<Int, MultiCameraClient.ICamera>()
    private val requestingPermission = AtomicBoolean(false)

    private var isCapturingVideo = false
    private var pendingOpen = false
    private var latestPreviewWidth = 0
    private var latestPreviewHeight = 0
    private var displayScale = 1f
    private var displayTranslationX = 0f
    private var displayTranslationY = 0f
    private var lastTouchX = 0f
    private var lastTouchY = 0f
    private val scaleGestureDetector = ScaleGestureDetector(context, PreviewScaleListener())
    private val gestureDetector = GestureDetector(context, PreviewGestureListener())

    init {
        rootView.addView(
            cameraView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        bindTextureLifecycle()
        bindPreviewGestures()
    }

    override fun getView(): View = rootView

    override fun dispose() {
        closeCameraInternal()
        unregisterCameraClient()
        rootView.removeAllViews()
    }

    fun initializeCamera() {
        // 如果 TextureView 已经准备好，且相机已连接等待打开，立即打开
        if (cameraView.surfaceTexture != null && pendingOpen && currentCamera != null) {
            tryOpenCurrentCamera()
        }
    }

    fun openCamera(result: MethodChannel.Result) {
        try {
            pendingOpen = true
            tryOpenCurrentCamera()
            result.success(null)
        } catch (e: Exception) {
            result.error("OPEN_FAILED", e.message, null)
        }
    }

    fun closeCamera(result: MethodChannel.Result) {
        pendingOpen = false
        closeCameraInternal()
        result.success(null)
    }

    fun takePicture(result: MethodChannel.Result) {
        val camera = getCurrentCamera()
        if (camera == null || !camera.isCameraOpened()) {
            result.error("NOT_OPENED", "摄像头未打开", null)
            return
        }

        camera.captureImage(object : ICaptureCallBack {
            override fun onBegin() {
                callFlutter("开始截图")
            }

            override fun onComplete(path: String?) {
                if (path.isNullOrEmpty()) {
                    result.error("CAPTURE_FAILED", "截图失败", null)
                    return
                }
                result.success(path)
                channel.invokeMethod("takePictureSuccess", path)
            }

            override fun onError(error: String?) {
                result.error("CAPTURE_FAILED", error, null)
            }
        }, null)
    }

    fun captureVideo(result: MethodChannel.Result) {
        val camera = getCurrentCamera()
        if (camera == null || !camera.isCameraOpened()) {
            result.error("NOT_OPENED", "摄像头未打开", null)
            return
        }

        if (isCapturingVideo) {
            camera.captureVideoStop()
            isCapturingVideo = false
            result.success("")
            return
        }

        camera.captureVideoStart(object : ICaptureCallBack {
            override fun onBegin() {
                isCapturingVideo = true
                callFlutter("开始录屏")
            }

            override fun onComplete(path: String?) {
                isCapturingVideo = false
                if (path.isNullOrEmpty()) {
                    result.error("VIDEO_FAILED", "录屏失败", null)
                    return
                }
                result.success(path)
            }

            override fun onError(error: String?) {
                isCapturingVideo = false
                result.error("VIDEO_FAILED", error, null)
            }
        }, null, 0L)
    }

    fun getAllPreviewSizes(): String? {
        val camera = getCurrentCamera()
        return if (camera is SeleneCameraUvc) {
            Gson().toJson(camera.getAllPreviewSizes())
        } else {
            null
        }
    }

    fun getCurrentCameraRequestParameters(): String? {
        val request = getCurrentCamera()?.getCameraRequest() ?: return null
        return Gson().toJson(request)
    }

    fun updateResolution(arguments: Any?) {
        val params = arguments as? Map<*, *> ?: return
        val width = (params["width"] as? Number)?.toInt() ?: return
        val height = (params["height"] as? Number)?.toInt() ?: return
        latestPreviewWidth = width
        latestPreviewHeight = height
        cameraView.surfaceTexture?.setDefaultBufferSize(width, height)
        getCurrentCamera()?.updateResolution(width, height)
    }

    fun setZoom(zoom: Int) {
        (getCurrentCamera() as? SeleneCameraUvc)?.setZoom(zoom)
    }

    fun getZoom(): Int {
        return (getCurrentCamera() as? SeleneCameraUvc)?.getZoom() ?: 0
    }

    fun getMaxZoom(): Int {
        return (getCurrentCamera() as? SeleneCameraUvc)?.getMaxZoom() ?: 0
    }

    fun resetZoom() {
        (getCurrentCamera() as? SeleneCameraUvc)?.resetZoom()
    }

    override fun onCameraState(
        self: MultiCameraClient.ICamera,
        code: ICameraStateCallBack.State,
        msg: String?,
    ) {
        when (code) {
            ICameraStateCallBack.State.OPENED -> {
                channel.invokeMethod("CameraState", "OPENED")
                (self as? SeleneCameraUvc)?.setButtonCallback(IButtonCallback { button, state ->
                    if (button == 1 && state == 1) {
                        takePicture(object : MethodChannel.Result {
                            override fun success(result: Any?) = Unit
                            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit
                            override fun notImplemented() = Unit
                        })
                    }
                })
            }

            ICameraStateCallBack.State.CLOSED -> channel.invokeMethod("CameraState", "CLOSED")
            ICameraStateCallBack.State.ERROR -> channel.invokeMethod("CameraState", "ERROR:${msg.orEmpty()}")
        }
    }

    private fun bindTextureLifecycle() {
        cameraView.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
                // 设置默认缓冲区大小
                val targetWidth = if (latestPreviewWidth > 0) latestPreviewWidth else BuildConfig.UVC_PREFERRED_WIDTH
                val targetHeight = if (latestPreviewHeight > 0) latestPreviewHeight else BuildConfig.UVC_PREFERRED_HEIGHT
                surface.setDefaultBufferSize(targetWidth, targetHeight)
                
                registerCameraClient()
                
                // 如果相机已经连接且等待打开，立即打开
                if (pendingOpen && currentCamera != null) {
                    tryOpenCurrentCamera()
                }
            }

            override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) {
                getCurrentCamera()?.setRenderSize(width, height)
            }

            override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
                closeCameraInternal()
                unregisterCameraClient()
                return true
            }

            override fun onSurfaceTextureUpdated(surface: SurfaceTexture) = Unit
        }
    }

    private fun registerCameraClient() {
        if (cameraClient != null) {
            // 如果 client 已注册，但 SurfaceTexture 刚准备好，检查是否需要打开相机
            if (pendingOpen && currentCamera != null && cameraView.surfaceTexture != null) {
                tryOpenCurrentCamera()
            }
            return
        }

        cameraClient = MultiCameraClient(activity, object : IDeviceConnectCallBack {
            override fun onAttachDev(device: UsbDevice?) {
                device ?: return
                if (cameraMap.containsKey(device.deviceId)) return
                cameraMap[device.deviceId] = SeleneCameraUvc(activity, device, cameraParams)
                if (requestingPermission.get()) return
                requestPermission(device)
            }

            override fun onDetachDec(device: UsbDevice?) {
                cameraMap.remove(device?.deviceId)?.setUsbControlBlock(null)
                requestingPermission.set(false)
                currentCamera?.cancel(true)
                currentCamera = null
                pendingOpen = false
            }

            override fun onConnectDev(device: UsbDevice?, ctrlBlock: USBMonitor.UsbControlBlock?) {
                device ?: return
                ctrlBlock ?: return
                val camera = cameraMap[device.deviceId] ?: return
                
                camera.setUsbControlBlock(ctrlBlock)
                currentCamera?.cancel(true)
                currentCamera = SettableFuture()
                currentCamera?.set(camera)
                requestingPermission.set(false)
                
                // 如果等待打开且 SurfaceTexture 已准备好，立即打开相机
                if (pendingOpen && cameraView.surfaceTexture != null) {
                    tryOpenCurrentCamera()
                }
            }

            override fun onDisConnectDec(device: UsbDevice?, ctrlBlock: USBMonitor.UsbControlBlock?) {
                closeCameraInternal()
                requestingPermission.set(false)
            }

            override fun onCancelDev(device: UsbDevice?) {
                requestingPermission.set(false)
            }
        })
        cameraClient?.register()
    }

    private fun unregisterCameraClient() {
        cameraMap.values.forEach { it.closeCamera() }
        cameraMap.clear()
        cameraClient?.unRegister()
        cameraClient?.destroy()
        cameraClient = null
        currentCamera?.cancel(true)
        currentCamera = null
    }

    private fun requestPermission(device: UsbDevice) {
        requestingPermission.set(true)
        cameraClient?.requestPermission(device)
    }

    private fun tryOpenCurrentCamera() {
        val camera = getCurrentCamera() ?: return
        
        // 确保 SurfaceTexture 已准备好
        val surfaceTexture = cameraView.surfaceTexture
        if (surfaceTexture == null) {
            pendingOpen = true
            return
        }
        
        pendingOpen = false
        
        // 设置默认缓冲区大小
        val request = getCameraRequest()
        surfaceTexture.setDefaultBufferSize(request.previewWidth, request.previewHeight)
        latestPreviewWidth = request.previewWidth
        latestPreviewHeight = request.previewHeight
        
        camera.openCamera(cameraView, request)
        camera.setCameraStateCallBack(this)
    }

    private fun getCurrentCamera(): MultiCameraClient.ICamera? {
        return try {
            currentCamera?.get(2, TimeUnit.SECONDS)
        } catch (e: Exception) {
            Logger.e("SeleneUvcView", "getCurrentCamera failed", e)
            null
        }
    }

    private fun closeCameraInternal() {
        getCurrentCamera()?.closeCamera()
        resetPreviewTransformState()
    }

    private fun callFlutter(message: String) {
        channel.invokeMethod(
            "callFlutter",
            mapOf(
                "type" to "msg",
                "msg" to message,
            ),
        )
    }

    private fun bindPreviewGestures() {
        cameraView.setOnTouchListener { _, event ->
            val scaleHandled = scaleGestureDetector.onTouchEvent(event)
            val gestureHandled = gestureDetector.onTouchEvent(event)

            if (!scaleGestureDetector.isInProgress && displayScale > 1f) {
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        lastTouchX = event.rawX
                        lastTouchY = event.rawY
                    }

                    MotionEvent.ACTION_MOVE -> {
                        val dx = event.rawX - lastTouchX
                        val dy = event.rawY - lastTouchY
                        lastTouchX = event.rawX
                        lastTouchY = event.rawY
                        displayTranslationX += dx
                        displayTranslationY += dy
                        applyPreviewTransform()
                    }

                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                        lastTouchX = 0f
                        lastTouchY = 0f
                    }
                }
            }

            scaleHandled || gestureHandled || displayScale > 1f
        }
    }

    private fun applyPreviewTransform() {
        val width = cameraView.width.toFloat()
        val height = cameraView.height.toFloat()
        if (width <= 0f || height <= 0f) {
            return
        }

        val maxTranslateX = (width * displayScale - width) / 2f
        val maxTranslateY = (height * displayScale - height) / 2f

        displayTranslationX = displayTranslationX.coerceIn(-maxTranslateX, maxTranslateX)
        displayTranslationY = displayTranslationY.coerceIn(-maxTranslateY, maxTranslateY)

        cameraView.pivotX = width / 2f
        cameraView.pivotY = height / 2f
        cameraView.scaleX = displayScale
        cameraView.scaleY = displayScale
        cameraView.translationX = displayTranslationX
        cameraView.translationY = displayTranslationY
    }

    private fun resetPreviewTransformState() {
        displayScale = 1f
        displayTranslationX = 0f
        displayTranslationY = 0f
        applyPreviewTransform()
    }

    private inner class PreviewScaleListener : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScale(detector: ScaleGestureDetector): Boolean {
            val nextScale = (displayScale * detector.scaleFactor).coerceIn(1f, 4f)
            if (nextScale == displayScale) {
                return false
            }
            displayScale = nextScale
            applyPreviewTransform()
            return true
        }
    }

    private inner class PreviewGestureListener : GestureDetector.SimpleOnGestureListener() {
        override fun onDoubleTap(e: MotionEvent): Boolean {
            resetPreviewTransformState()
            return true
        }
    }

    private fun getCameraRequest(): com.jiangdg.ausbc.camera.bean.CameraRequest {
        // 使用 NORMAL 渲染模式直接渲染到 TextureView，避免 OPENGL 模式下的黑屏问题
        return com.jiangdg.ausbc.camera.bean.CameraRequest.Builder()
            .setPreviewWidth(BuildConfig.UVC_PREFERRED_WIDTH)
            .setPreviewHeight(BuildConfig.UVC_PREFERRED_HEIGHT)
            .setRenderMode(com.jiangdg.ausbc.camera.bean.CameraRequest.RenderMode.NORMAL)
            .setDefaultRotateType(com.jiangdg.ausbc.render.env.RotateType.ANGLE_0)
            .setAudioSource(com.jiangdg.ausbc.camera.bean.CameraRequest.AudioSource.SOURCE_SYS_MIC)
            .setAspectRatioShow(true)
            .setCaptureRawImage(false)
            .setRawPreviewData(false)
            .create()
    }

    private fun buildCameraParams(args: Any?): Map<String, Any> {
        val defaults = mutableMapOf<String, Any>(
            "preferredWidth" to BuildConfig.UVC_PREFERRED_WIDTH,
            "preferredHeight" to BuildConfig.UVC_PREFERRED_HEIGHT,
            "minFps" to BuildConfig.UVC_MIN_FPS,
            "maxFps" to BuildConfig.UVC_MAX_FPS,
            "frameFormat" to BuildConfig.UVC_FRAME_FORMAT,
            "bandwidthFactor" to BuildConfig.UVC_BANDWIDTH_FACTOR,
        )

        val incoming = (args as? Map<*, *>)?.mapKeys { it.key.toString() } ?: emptyMap()
        incoming.forEach { (key, value) ->
            if (value != null) {
                defaults[key] = value
            }
        }
        return defaults
    }
}
