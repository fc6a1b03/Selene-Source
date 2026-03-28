package com.selene.uvc

import android.content.ContentValues
import android.content.Context
import android.graphics.SurfaceTexture
import android.hardware.usb.UsbDevice
import android.media.MediaScannerConnection
import android.provider.MediaStore
import android.view.Surface
import android.view.SurfaceView
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

        try {
            initEncodeProcessor(previewSize.width, previewSize.height)
            uvcCamera?.setPreviewSize(
                previewSize.width,
                previewSize.height,
                minFps,
                maxFps,
                frameFormat,
                bandwidthFactor,
            )
        } catch (e: Exception) {
            previewSize = choosePreviewSize(preferredWidth, preferredHeight).apply {
                request.previewWidth = width
                request.previewHeight = height
            }
            uvcCamera?.setPreviewSize(
                previewSize.width,
                previewSize.height,
                minFps,
                maxFps,
                UVCCamera.FRAME_FORMAT_YUYV,
                UVCCamera.DEFAULT_BANDWIDTH,
            )
        }

        if (!isNeedGLESRender || request.isRawPreviewData || request.isCaptureRawImage) {
            uvcCamera?.setFrameCallback(frameCallback, UVCCamera.PIXEL_FORMAT_YUV420SP)
        }

        when (cameraView) {
            is Surface -> uvcCamera?.setPreviewDisplay(cameraView)
            is SurfaceTexture -> {
                cameraView.setDefaultBufferSize(previewSize.width, previewSize.height)
                uvcCamera?.setPreviewTexture(cameraView)
            }
            is SurfaceView -> uvcCamera?.setPreviewDisplay(cameraView.holder)
            is TextureView -> {
                cameraView.surfaceTexture?.setDefaultBufferSize(previewSize.width, previewSize.height)
                uvcCamera?.setPreviewTexture(cameraView.surfaceTexture)
            }
            else -> throw IllegalStateException("Only support Surface/SurfaceTexture/SurfaceView/TextureView")
        }

        uvcCamera?.autoFocus = true
        uvcCamera?.autoWhiteBlance = true
        uvcCamera?.startPreview()
        uvcCamera?.updateCameraParams()
        isPreviewed = true
        postStateEvent(ICameraStateCallBack.State.OPENED)
        Logger.i(TAG, "start preview size=$previewSize")
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
            if (!CameraUtils.hasStoragePermission(ctx)) {
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
            val date = mDateFormat.format(System.currentTimeMillis())
            val title = savePath ?: "IMG_UVC_$date"
            val displayName = savePath ?: "$title.jpg"
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
                put(MediaStore.Images.ImageColumns.DATE_TAKEN, date)
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
