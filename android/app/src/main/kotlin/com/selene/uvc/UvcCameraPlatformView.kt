package com.selene.uvc

import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.graphics.SurfaceTexture
import android.hardware.usb.UsbDevice
import android.media.MediaScannerConnection
import android.os.Environment
import android.os.Build
import android.provider.MediaStore
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
import com.jiangdg.ausbc.widget.AspectRatioTextureView
import com.jiangdg.usb.USBMonitor
import com.jiangdg.uvc.IButtonCallback
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import org.moontechlab.selene.BuildConfig
import java.io.File
import java.text.SimpleDateFormat
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.Locale

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
    private val cameraView = AspectRatioTextureView(context)
    private val cameraParams = buildCameraParams(args)

    private var cameraClient: MultiCameraClient? = null
    private var currentCamera: SettableFuture<MultiCameraClient.ICamera>? = null
    private val cameraMap = hashMapOf<Int, MultiCameraClient.ICamera>()
    private val requestingPermission = AtomicBoolean(false)

    private var isCapturingVideo = false
    private var pendingOpen = false
    private var latestPreviewWidth = 0
    private var latestPreviewHeight = 0
    private var hasRenderedFirstFrame = false
    private var pendingRecordingPath: String? = null
    private val mediaPublishExecutor = Executors.newSingleThreadExecutor()
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
        pendingOpen = false
        cameraView.surfaceTextureListener = null
        cameraView.setOnTouchListener(null)
        closeCameraInternal()
        unregisterCameraClient()
        latestPreviewWidth = 0
        latestPreviewHeight = 0
        hasRenderedFirstFrame = false
        pendingRecordingPath = null
        mediaPublishExecutor.shutdownNow()
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

    fun startVideoRecording(result: MethodChannel.Result) {
        val camera = getCurrentCamera()
        if (camera == null || !camera.isCameraOpened()) {
            result.error("NOT_OPENED", "摄像头未打开", null)
            return
        }

        if (isCapturingVideo) {
            result.error("ALREADY_RECORDING", "录像已在进行中", null)
            return
        }

        val recordingBasePath = buildRecordingOutputBasePath()
        pendingRecordingPath = recordingBasePath?.let { "$it.mp4" }
        var startAcknowledged = false
        try {
            camera.captureVideoStart(object : ICaptureCallBack {
                override fun onBegin() {
                    isCapturingVideo = true
                    startAcknowledged = true
                    callFlutter("开始录屏")
                    result.success(null)
                }

            override fun onComplete(path: String?) {
                isCapturingVideo = false
                val completedPath = path ?: pendingRecordingPath
                pendingRecordingPath = null
                if (!startAcknowledged) {
                    if (completedPath.isNullOrEmpty()) {
                        result.error("VIDEO_FAILED", "录屏失败", null)
                    } else {
                        result.success(null)
                        publishRecordingResult(completedPath)
                    }
                    return
                }
                if (completedPath.isNullOrEmpty()) {
                    channel.invokeMethod("videoRecordingError", "录屏失败")
                    return
                }
                publishRecordingResult(completedPath)
            }

            override fun onError(error: String?) {
                isCapturingVideo = false
                val fallbackPath = pendingRecordingPath
                pendingRecordingPath = null
                if (isMediaStoreMutationError(error) && !fallbackPath.isNullOrEmpty()) {
                    val file = File(fallbackPath)
                    if (file.exists() && file.length() > 0L) {
                        publishRecordingResult(fallbackPath)
                        return
                    }
                }
                if (!startAcknowledged) {
                    result.error("VIDEO_FAILED", error ?: "录屏失败", null)
                    return
                }
                channel.invokeMethod("videoRecordingError", error ?: "录屏失败")
                }
            }, recordingBasePath, 0L)
        } catch (e: Exception) {
            isCapturingVideo = false
            pendingRecordingPath = null
            result.error("VIDEO_FAILED", e.message ?: "录屏失败", null)
        }
    }

    fun stopVideoRecording(result: MethodChannel.Result) {
        val camera = getCurrentCamera()
        if (camera == null || !camera.isCameraOpened()) {
            result.error("NOT_OPENED", "摄像头未打开", null)
            return
        }

        if (!isCapturingVideo) {
            result.success(null)
            return
        }

        try {
            camera.captureVideoStop()
            result.success(null)
        } catch (e: Exception) {
            val fallbackPath = pendingRecordingPath
            pendingRecordingPath = null
            if (isMediaStoreMutationError(e.message) && !fallbackPath.isNullOrEmpty()) {
                val file = File(fallbackPath)
                if (file.exists() && file.length() > 0L) {
                    isCapturingVideo = false
                    publishRecordingResult(fallbackPath)
                    result.success(null)
                    return
                }
            }
            result.error("VIDEO_FAILED", e.message ?: "停止录屏失败", null)
        }
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

            override fun onSurfaceTextureUpdated(surface: SurfaceTexture) {
                if (!hasRenderedFirstFrame) {
                    hasRenderedFirstFrame = true
                    callFlutter("预览首帧已到达")
                }
                // Flutter 官方文档要求: PlatformView 内包含 SurfaceTexture 时，
                // 内容更新后需要手动触发 invalidate，否则可能长期停留在黑帧。
                cameraView.invalidate()
                rootView.invalidate()
                rootView.postInvalidateOnAnimation()
            }
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
                cameraMap[device.deviceId] = SeleneCameraUvc(
                    activity,
                    device,
                    cameraParams,
                )
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
        
        // 确保 TextureView 已经附加到窗口并有有效尺寸
        if (cameraView.width <= 0 || cameraView.height <= 0) {
            pendingOpen = true
            // 延迟重试
            cameraView.postDelayed({ tryOpenCurrentCamera() }, 100)
            return
        }
        
        pendingOpen = false

        // 打开相机
        hasRenderedFirstFrame = false
        val request = getCameraRequest()
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
        hasRenderedFirstFrame = false
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

    private fun isMediaStoreMutationError(message: String?): Boolean {
        val normalized = message?.lowercase() ?: return false
        return normalized.contains("mutation of _data is not allowed")
    }

    private fun publishRecordingResult(sourcePath: String) {
        mediaPublishExecutor.execute {
            val finalPath = publishVideoToMediaStore(sourcePath) ?: sourcePath
            activity.runOnUiThread {
                channel.invokeMethod("videoRecordingCompleted", finalPath)
            }
        }
    }

    private fun publishVideoToMediaStore(sourcePath: String): String? {
        val sourceFile = File(sourcePath)
        if (!sourceFile.exists() || sourceFile.length() <= 0L) {
            return null
        }

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Video.Media.DISPLAY_NAME, sourceFile.name)
                    put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                    put(
                        MediaStore.Video.Media.RELATIVE_PATH,
                        Environment.DIRECTORY_MOVIES + File.separator + "Selene",
                    )
                    put(MediaStore.Video.Media.IS_PENDING, 1)
                }

                val resolver = activity.contentResolver
                val uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
                    ?: return null

                try {
                    resolver.openOutputStream(uri)?.use { output ->
                        sourceFile.inputStream().use { input ->
                            input.copyTo(output)
                        }
                    } ?: return null

                    val readyValues = ContentValues().apply {
                        put(MediaStore.Video.Media.IS_PENDING, 0)
                    }
                    resolver.update(uri, readyValues, null, null)
                    sourceFile.delete()
                    uri.toString()
                } catch (e: Exception) {
                    resolver.delete(uri, null, null)
                    throw e
                }
            } else {
                MediaScannerConnection.scanFile(
                    activity,
                    arrayOf(sourceFile.absolutePath),
                    arrayOf("video/mp4"),
                    null,
                )
                sourceFile.absolutePath
            }
        } catch (e: Exception) {
            Logger.e(TAG, "publish video to media store failed", e)
            null
        }
    }

    private fun buildRecordingOutputBasePath(): String? {
        val moviesDir = activity.getExternalFilesDir(Environment.DIRECTORY_MOVIES)
            ?: activity.filesDir
        val targetDir = File(moviesDir, "selene_usb_capture")
        if (!targetDir.exists() && !targetDir.mkdirs()) {
            Logger.w(TAG, "create recording directory failed: ${targetDir.absolutePath}")
            return null
        }
        val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US)
            .format(System.currentTimeMillis())
        return File(targetDir, "VID_UVC_$timestamp").absolutePath
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
        override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
            channel.invokeMethod("previewTapped", null)
            return true
        }

        override fun onDoubleTap(e: MotionEvent): Boolean {
            resetPreviewTransformState()
            return true
        }
    }

    private fun getCameraRequest(): com.jiangdg.ausbc.camera.bean.CameraRequest {
        // 先用更稳的 720p 建立首帧预览，待画面稳定后再自动切换到设备支持的最佳分辨率。
        return com.jiangdg.ausbc.camera.bean.CameraRequest.Builder()
            .setPreviewWidth(1280)
            .setPreviewHeight(720)
            .setRenderMode(com.jiangdg.ausbc.camera.bean.CameraRequest.RenderMode.OPENGL)
            .setDefaultRotateType(com.jiangdg.ausbc.render.env.RotateType.ANGLE_0)
            .setAudioSource(com.jiangdg.ausbc.camera.bean.CameraRequest.AudioSource.SOURCE_SYS_MIC)
            .setAspectRatioShow(true)
            .setCaptureRawImage(false)
            .setRawPreviewData(false)
            .create()
    }

    private fun buildCameraParams(args: Any?): Map<String, Any> {
        val defaults = mutableMapOf<String, Any>(
            // 优先使用设备声明的目标分辨率；若失败，再由底层回退到更稳的档位。
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
