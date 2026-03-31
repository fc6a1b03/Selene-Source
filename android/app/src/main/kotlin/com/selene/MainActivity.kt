package org.moontechlab.selene

import android.app.Activity
import android.content.Intent
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import com.selene.usb.UsbCapturePlugin
import com.selene.uvc.UvcCameraPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val NATIVE_FILE_CHANNEL = "selene.native_file_access/channel"
        private const val REQUEST_PICK_IMPORT_FILE = 4101
        private const val REQUEST_CREATE_EXPORT_FILE = 4102
    }

    private var usbCapturePlugin: UsbCapturePlugin? = null
    private var uvcCameraPlugin: UvcCameraPlugin? = null
    private var nativeFileChannel: MethodChannel? = null
    private var pendingImportResult: MethodChannel.Result? = null
    private var pendingExportResult: MethodChannel.Result? = null
    private var pendingExportBytes: ByteArray? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleUsbIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleUsbIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        usbCapturePlugin = UsbCapturePlugin.registerWith(flutterEngine, this)
        uvcCameraPlugin = UvcCameraPlugin.registerWith(flutterEngine, this)
        nativeFileChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NATIVE_FILE_CHANNEL
        ).also { channel ->
            channel.setMethodCallHandler(::handleNativeFileCall)
        }
    }

    override fun onDestroy() {
        nativeFileChannel?.setMethodCallHandler(null)
        pendingImportResult = null
        pendingExportResult = null
        pendingExportBytes = null
        usbCapturePlugin?.dispose()
        uvcCameraPlugin?.dispose()
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        when (requestCode) {
            REQUEST_PICK_IMPORT_FILE -> {
                val result = pendingImportResult
                pendingImportResult = null
                if (result == null) {
                    return
                }

                if (resultCode != Activity.RESULT_OK || data?.data == null) {
                    result.success(null)
                    return
                }

                val uri = data.data ?: run {
                    result.success(null)
                    return
                }

                try {
                    val bytes = contentResolver.openInputStream(uri)?.use { input ->
                        input.readBytes()
                    } ?: byteArrayOf()
                    result.success(
                        mapOf(
                            "name" to queryDisplayName(uri),
                            "bytes" to bytes
                        )
                    )
                } catch (error: Exception) {
                    result.error("READ_FAILED", error.message, null)
                }
            }

            REQUEST_CREATE_EXPORT_FILE -> {
                val result = pendingExportResult
                val bytes = pendingExportBytes
                pendingExportResult = null
                pendingExportBytes = null
                if (result == null) {
                    return
                }

                if (resultCode != Activity.RESULT_OK || data?.data == null || bytes == null) {
                    result.success(null)
                    return
                }

                val uri = data.data ?: run {
                    result.success(null)
                    return
                }

                try {
                    contentResolver.openOutputStream(uri)?.use { output ->
                        output.write(bytes)
                        output.flush()
                    } ?: throw IllegalStateException("无法写入导出文件")
                    result.success(mapOf("uri" to uri.toString()))
                } catch (error: Exception) {
                    result.error("WRITE_FAILED", error.message, null)
                }
            }
        }
    }

    private fun handleUsbIntent(intent: Intent?) {
        if (intent?.action == UsbManager.ACTION_USB_DEVICE_ATTACHED) {
            val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
            }
            device?.let {
                android.util.Log.d(
                    "MainActivity",
                    "USB 设备通过 Intent 连接: ${it.productName}"
                )
            }
        }
    }

    private fun handleNativeFileCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickImportFile" -> openImportFilePicker(result)
            "saveExportFile" -> saveExportFile(call, result)
            else -> result.notImplemented()
        }
    }

    private fun openImportFilePicker(result: MethodChannel.Result) {
        if (pendingImportResult != null) {
            result.error("PICK_IN_PROGRESS", "已有文件选择任务进行中", null)
            return
        }

        pendingImportResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }
        startActivityForResult(intent, REQUEST_PICK_IMPORT_FILE)
    }

    private fun saveExportFile(call: MethodCall, result: MethodChannel.Result) {
        if (pendingExportResult != null) {
            result.error("SAVE_IN_PROGRESS", "已有文件保存任务进行中", null)
            return
        }

        val bytes = call.argument<ByteArray>("bytes")
        val suggestedName = call.argument<String>("suggestedName") ?: "selene-backup.dat"
        if (bytes == null) {
            result.error("MISSING_BYTES", "缺少导出文件内容", null)
            return
        }

        pendingExportBytes = bytes
        pendingExportResult = result
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, suggestedName)
        }
        startActivityForResult(intent, REQUEST_CREATE_EXPORT_FILE)
    }

    private fun queryDisplayName(uri: android.net.Uri): String {
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (nameIndex >= 0 && cursor.moveToFirst()) {
                return cursor.getString(nameIndex)
            }
        }
        return uri.lastPathSegment ?: "backup.dat"
    }
}
