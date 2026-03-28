package com.selene.uvc

import android.content.ContentValues
import android.content.Context
import android.graphics.SurfaceTexture
import android.hardware.usb.UsbDevice
import android.os.Build
import android.os.Environment
import android.media.MediaScannerConnection
import android.provider.MediaStore
import android.view.Surface
import android.view.TextureView
import com.jiangdg.ausbc.MultiCameraClient
import com.jiangdg.ausbc.MultiCameraClient.Companion.CAPTURE_TIMES_OUT_SEC
import com.jiangdg.ausbc.MultiCameraClient.Companion.MAX_NV21_DATA
import com.jiangdg.ausbc.callback.ICameraStateCallBack
import com.jiangdg.ausbc.callback.ICaptureCallBack
import com.jiangdg.ausbc.callback.IPreviewDataCallBack
import com.jiangdg.ausbc.camera.bean.CameraRequest
import com.jiangdg.ausbc.camera.bean.PreviewSize
import com.jiangdg.ausbc.utils.CameraUtils
import com.jiangdg.ausbc.utils.Logger
import com.jiangdg.ausbc.utils.MediaUtils
import com.jiangdg.ausbc.utils.Utils
import com.jiangdg.uvc.IButtonCallback
import com.jiangdg.uvc.IFrameCallback
import com.jiangdg.uvc.UVCCamera
import java.io.File
import java.util.concurrent.TimeUnit

class SeleneCameraUvc(
    ctx: Context,
    device: UsbDevice,
    private val params: Map<String, *>?,
    private val onPreviewSizeChanged: ((width: Int, height: Int) -> Unit)? = null,
) : MultiCameraClient.ICamera(ctx, device) {

    companion object {
        private const val TAG = "SeleneCameraUvc"
    }

    private var uvcCamera: UVCCamera? = null
    private val previewSizes = arrayListOf<PreviewSize>()

    private val frameCallback = IFrameCallback { frame ->
        frame?.apply {
            position(0)
            val data = ByteArray(capacity())
            get(data)
            mCameraRequest?.apply {
                if (data.size != previewWidth * previewHeight * 3 / 2) {
                    return@IFrameCallback
                }
                mPreviewDataCbList.forEach { cb ->
                    cb?.onPreviewData(data, previewWidth, previewHeight, IPreviewDataCallBack.DataFormat.NV21)
                }
                if (mNV21DataQueue.size >= MAX_NV21_DATA) {
                    mNV21DataQueue.removeLast()
                }
                mNV21DataQueue.offerFirst(data)
                putVideoData(data)
            }
        }
    }

    override fun getAllPreviewSizes(aspectRatio: Double?): MutableList<PreviewSize> {
        val supported = arrayListOf<PreviewSize>()
        val sizeList = if (uvcCamera?.supportedSizeList?.isNullOrEmpty() == false) {
            uvcCamera?.supportedSizeList
        } else {
            uvcCamera?.getSupportedSizeList(UVCCamera.FRAME_FORMAT_YUYV)
        } ?: return supported

        if (previewSizes.isEmpty()) {
            previewSizes.clear()
            sizeList.forEach { size ->
                previewSizes.add(PreviewSize(size.width, size.height))
            }
        }

        previewSizes.forEach { size ->
            val ratio = size.width.toDouble() / size.height.toDouble()
            if (aspectRatio == null || ratio == aspectRatio) {
                supported.add(size)
            }
        }
        return supported
    }

    override fun <T> openCameraInternal(cameraView: T) {
        if (Utils.isTargetSdkOverP(ctx) && !CameraUtils.hasCameraPermission(ctx)) {
            closeCamera()
            postStateEvent(ICameraStateCallBack.State.ERROR, "Has no CAMERA permission.")
            return
        }
        if (mCtrlBlock == null) {
            closeCamera()
            postStateEvent(ICameraStateCallBack.State.ERROR, "Usb control block can not be null")
            return
        }

        val request = mCameraRequest ?: run {
            postStateEvent(ICameraStateCallBack.State.ERROR, "Camera request missing")
            return
        }

        try {
            uvcCamera = UVCCamera().apply {
                open(mCtrlBlock)
            }
        } catch (e: Exception) {
            closeCamera()
            postStateEvent(ICameraStateCallBack.State.ERROR, "open camera failed ${e.localizedMessage}")
            return
        }

        val preferredWidth = (params?.get("preferredWidth") as? Number)?.toInt()
        val preferredHeight = (params?.get("preferredHeight") as? Number)?.toInt()
        val minFps = (params?.get("minFps") as? Number)?.toInt() ?: 10
        val maxFps = (params?.get("maxFps") as? Number)?.toInt() ?: 60
        val frameFormat = (params?.get("frameFormat") as? Number)?.toInt() ?: UVCCamera.FRAME_FORMAT_MJPEG
        val bandwidthFactor = (params?.get("bandwidthFactor") as? Number)?.toFloat() ?: UVCCamera.DEFAULT_BANDWIDTH

        var previewSize = choosePreviewSize(preferredWidth, preferredHeight).apply {
            request.previewWidth = width
            request.previewHeight = height
        }

        // 尝试设置预览尺寸，先尝试 MJPEG，然后 YUYV，如果都失败则尝试常见分辨率
        var previewSetSuccess = false
        var finalPreviewSize = previewSize
        
        // 尝试 1: MJPEG 格式（首选）
        try {
            uvcCamera?.setPreviewSize(
                previewSize.width,
                previewSize.height,
                minFps,
                maxFps,
                UVCCamera.FRAME_FORMAT_MJPEG,
                bandwidthFactor,
            )
            finalPreviewSize = previewSize
            previewSetSuccess = true
        } catch (e: Exception) {
            // 尝试 2: YUYV 格式（选择的分辨率）
            if (!previewSetSuccess) {
                try {
                    val altSize = choosePreviewSize(preferredWidth, preferredHeight)
                    uvcCamera?.setPreviewSize(
                        altSize.width,
                        altSize.height,
                        minFps,
                        maxFps,
                        UVCCamera.FRAME_FORMAT_YUYV,
                        UVCCamera.DEFAULT_BANDWIDTH,
                    )
                    finalPreviewSize = altSize
                    previewSetSuccess = true
                } catch (e2: Exception) {
                    // 忽略，继续尝试
                }
            }
            
            // 尝试 3: 常见分辨率 640x480 YUYV
            if (!previewSetSuccess) {
                try {
                    uvcCamera?.setPreviewSize(
                        640, 480,
                        minFps,
                        maxFps,
                        UVCCamera.FRAME_FORMAT_YUYV,
                        UVCCamera.DEFAULT_BANDWIDTH,
                    )
                    finalPreviewSize = PreviewSize(640, 480)
                    previewSetSuccess = true
                } catch (e3: Exception) {
                    // 忽略
                }
            }
            
            // 尝试 4: 常见分辨率 1280x720 YUYV
            if (!previewSetSuccess) {
                try {
                    uvcCamera?.setPreviewSize(
                        1280, 720,
                        minFps,
                        maxFps,
                        UVCCamera.FRAME_FORMAT_YUYV,
                        UVCCamera.DEFAULT_BANDWIDTH,
                    )
                    finalPreviewSize = PreviewSize(1280, 720)
                    previewSetSuccess = true
                } catch (e4: Exception) {
                    // 忽略
                }
            }
        }
        
        if (!previewSetSuccess) {
            closeCamera()
            postStateEvent(ICameraStateCallBack.State.ERROR, "set preview size failed, tried multiple formats and resolutions")
            return
        }
        
        // 使用成功设置的尺寸
        previewSize = finalPreviewSize
        request.previewWidth = previewSize.width
        request.previewHeight = previewSize.height
        
        // 记录实际预览尺寸，必要时再由上层使用。
        onPreviewSizeChanged?.invoke(previewSize.width, previewSize.height)
        
        // 初始化编码处理器
        initEncodeProcessor(previewSize.width, previewSize.height)

        // 在 NORMAL 模式下设置帧回调
        if (!isNeedGLESRender || request.isRawPreviewData || request.isCaptureRawImage) {
            uvcCamera?.setFrameCallback(frameCallback, UVCCamera.PIXEL_FORMAT_YUV420SP)
        }

        when (cameraView) {
            is Surface -> uvcCamera?.setPreviewDisplay(cameraView)
            is SurfaceTexture -> uvcCamera?.setPreviewTexture(cameraView)
            is TextureView -> {
                val surfaceTexture = cameraView.surfaceTexture
                if (surfaceTexture == null) {
                    closeCamera()
                    postStateEvent(ICameraStateCallBack.State.ERROR, "TextureView surfaceTexture is null")
                    return
                }
                uvcCamera?.setPreviewTexture(surfaceTexture)
            }
            else -> throw IllegalStateException("Only support Surface/SurfaceTexture/SurfaceView/TextureView")
        }

        uvcCamera?.autoFocus = true
        uvcCamera?.autoWhiteBlance = true
        uvcCamera?.startPreview()
        uvcCamera?.updateCameraParams()
        isPreviewed = true
        postStateEvent(ICameraStateCallBack.State.OPENED)
    }

    override fun closeCameraInternal() {
        postStateEvent(ICameraStateCallBack.State.CLOSED)
        isPreviewed = false
        releaseEncodeProcessor()
        uvcCamera?.destroy()
        uvcCamera = null
    }

    override fun captureImageInternal(savePath: String?, callback: ICaptureCallBack) {
        mSaveImageExecutor.submit {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q && !CameraUtils.hasStoragePermission(ctx)) {
                mMainHandler.post { callback.onError("have no storage permission") }
                return@submit
            }
            if (!isPreviewed) {
                mMainHandler.post { callback.onError("camera not previewing") }
                return@submit
            }
            val data = mNV21DataQueue.pollFirst(CAPTURE_TIMES_OUT_SEC, TimeUnit.SECONDS)
            if (data == null) {
                mMainHandler.post { callback.onError("Times out") }
                return@submit
            }
            mMainHandler.post { callback.onBegin() }
            val capturedAt = System.currentTimeMillis()
            val date = mDateFormat.format(capturedAt)
            val title = savePath ?: "IMG_UVC_$date"
            val displayName = savePath ?: "$title.jpg"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val tempFile = File(ctx.cacheDir, displayName)
                val ret = MediaUtils.saveYuv2Jpeg(
                    tempFile.absolutePath,
                    data,
                    mCameraRequest!!.previewWidth,
                    mCameraRequest!!.previewHeight,
                )
                if (!ret) {
                    tempFile.delete()
                    mMainHandler.post { callback.onError("save yuv to jpeg failed.") }
                    return@submit
                }
                try {
                    val values = ContentValues().apply {
                        put(MediaStore.Images.ImageColumns.TITLE, title)
                        put(MediaStore.Images.ImageColumns.DISPLAY_NAME, displayName)
                        put(MediaStore.Images.ImageColumns.MIME_TYPE, "image/jpeg")
                        put(MediaStore.Images.ImageColumns.DATE_TAKEN, capturedAt)
                        put(
                            MediaStore.Images.ImageColumns.RELATIVE_PATH,
                            Environment.DIRECTORY_DCIM + File.separator + "Camera",
                        )
                        put(MediaStore.Images.ImageColumns.IS_PENDING, 1)
                    }
                    val uri = ctx.contentResolver?.insert(
                        MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                        values,
                    )
                    if (uri == null) {
                        tempFile.delete()
                        mMainHandler.post { callback.onError("insert image to MediaStore failed.") }
                        return@submit
                    }
                    ctx.contentResolver?.openOutputStream(uri)?.use { output ->
                        tempFile.inputStream().use { input ->
                            input.copyTo(output)
                        }
                    } ?: run {
                        tempFile.delete()
                        mMainHandler.post { callback.onError("open MediaStore output stream failed.") }
                        return@submit
                    }
                    val readyValues = ContentValues().apply {
                        put(MediaStore.Images.ImageColumns.IS_PENDING, 0)
                    }
                    ctx.contentResolver?.update(uri, readyValues, null, null)
                    tempFile.delete()
                    mMainHandler.post { callback.onComplete(uri.toString()) }
                } catch (e: Exception) {
                    tempFile.delete()
                    mMainHandler.post { callback.onError(e.localizedMessage ?: "save image failed.") }
                }
                return@submit
            }

            val path = savePath ?: "$mCameraDir/$displayName"
            val ret = MediaUtils.saveYuv2Jpeg(path, data, mCameraRequest!!.previewWidth, mCameraRequest!!.previewHeight)
            if (!ret) {
                File(path).delete()
                mMainHandler.post { callback.onError("save yuv to jpeg failed.") }
                return@submit
            }
            val values = ContentValues().apply {
                put(MediaStore.Images.ImageColumns.TITLE, title)
                put(MediaStore.Images.ImageColumns.DISPLAY_NAME, displayName)
                put(MediaStore.Images.ImageColumns.DATA, path)
                put(MediaStore.Images.ImageColumns.DATE_TAKEN, capturedAt)
            }
            ctx.contentResolver?.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            MediaScannerConnection.scanFile(ctx, arrayOf(path), null, null)
            mMainHandler.post { callback.onComplete(path) }
        }
    }

    fun setZoom(zoom: Int) {
        val minZoom = getMinZoom()
        val maxZoom = getMaxZoom()
        val target = if (maxZoom > minZoom) {
            zoom.coerceIn(minZoom, maxZoom)
        } else {
            zoom
        }
        uvcCamera?.zoom = target
    }

    fun getZoom(): Int {
        return uvcCamera?.zoom ?: 0
    }

    fun getMaxZoom(): Int {
        return readCameraIntField("mZoomMax")
    }

    fun getMinZoom(): Int {
        return readCameraIntField("mZoomMin")
    }

    fun resetZoom() {
        uvcCamera?.resetZoom()
    }

    fun setButtonCallback(callback: IButtonCallback?) {
        uvcCamera?.setButtonCallback(callback)
    }

    private fun choosePreviewSize(preferredWidth: Int?, preferredHeight: Int?): PreviewSize {
        val sizes = getAllPreviewSizes()
        if (sizes.isEmpty()) {
            return PreviewSize(640, 480)
        }

        if (preferredWidth != null && preferredHeight != null) {
            sizes.firstOrNull { it.width == preferredWidth && it.height == preferredHeight }?.let { return it }
        }

        return sizes.maxByOrNull { it.width * it.height } ?: sizes.first()
    }

    private fun readCameraIntField(fieldName: String): Int {
        val camera = uvcCamera ?: return 0
        return try {
            val field = UVCCamera::class.java.getDeclaredField(fieldName)
            field.isAccessible = true
            field.getInt(camera)
        } catch (e: Exception) {
            Logger.w(TAG, "read $fieldName failed: ${e.message}")
            0
        }
    }
}
