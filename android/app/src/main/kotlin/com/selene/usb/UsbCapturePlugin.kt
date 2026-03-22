package com.selene.usb

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler

/**
 * USB 采集卡平台通道插件
 *
 * 实现 USB 设备检测功能，与 Flutter 端通信
 */
class UsbCapturePlugin(
    private val context: Context
) : MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val CHANNEL_NAME = "selene.usb_capture/channel"
        const val EVENT_CHANNEL_NAME = "selene.usb_capture/events"
        const val ACTION_USB_PERMISSION = "com.selene.USB_PERMISSION"

        // 常见采集卡 VID/PID 列表
        private val CAPTURE_CARD_SIGNATURES = mapOf(
            0x534d to listOf(0x2109, 0x2130), // MacroSilicon MS2109/MS2130
            0xeb1a to listOf(0x2860, 0x2870, 0x2820), // Empia EM28xx
            0x05e1 to listOf(0x0408), // Syntek
            0x1b71 to listOf(0x3002, 0x3003), // Fushicai
            0x046d to emptyList() // Logitech (所有产品)
        )

        fun registerWith(engine: FlutterEngine, context: Context): UsbCapturePlugin {
            val plugin = UsbCapturePlugin(context)

            MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)
                .setMethodCallHandler(plugin)

            EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL_NAME)
                .setStreamHandler(plugin)

            return plugin
        }
    }

    private val usbManager: UsbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private var eventSink: EventChannel.EventSink? = null
    private var usbReceiver: BroadcastReceiver? = null

    // 当前连接的采集卡设备
    private var connectedDevice: UsbDevice? = null

    init {
        registerUsbReceiver()
        checkExistingDevices()
    }

    /**
     * 检查已连接的 USB 设备
     */
    private fun checkExistingDevices() {
        val deviceList = usbManager.deviceList
        android.util.Log.d("UsbCapturePlugin", "检查已连接设备，共 ${deviceList.size} 个")

        for ((name, device) in deviceList) {
            val vid = device.vendorId
            val pid = device.productId
            android.util.Log.d(
                "UsbCapturePlugin",
                "设备: $name, VID: 0x${vid.toString(16)}, PID: 0x${pid.toString(16)}, 名称: ${device.productName}"
            )

            // 检测：VID/PID 匹配 或 UVC 设备 或 产品名关键词
            if (isKnownCaptureCard(vid, pid) || isUvcDevice(device) || isCaptureCardByName(device)) {
                connectedDevice = device
                android.util.Log.d(
                    "UsbCapturePlugin",
                    "✓ 发现采集卡: ${device.productName} (0x${vid.toString(16)}:0x${pid.toString(16)})"
                )
                break
            }
        }

        if (connectedDevice == null) {
            android.util.Log.d("UsbCapturePlugin", "未找到采集卡设备")
        }
    }

    /**
     * 通过 VID/PID 检查是否是已知采集卡
     */
    private fun isKnownCaptureCard(vid: Int, pid: Int): Boolean {
        val knownPids = CAPTURE_CARD_SIGNATURES[vid]
        return if (knownPids != null) {
            knownPids.isEmpty() || knownPids.contains(pid)
        } else {
            false
        }
    }

    /**
     * 通过产品名称检查是否是采集卡
     */
    private fun isCaptureCardByName(device: UsbDevice): Boolean {
        val productName = device.productName?.lowercase() ?: ""
        val keywords = listOf("capture", "video", "camera", "hdmi", "采集卡", "摄像头", "webcam", "uvc")
        return keywords.any { productName.contains(it) }
    }

    /**
     * 识别芯片型号
     */
    private fun identifyChip(vid: Int, pid: Int): String {
        return when (vid) {
            0x534d -> when (pid) {
                0x2109 -> "MacroSilicon MS2109"
                0x2130 -> "MacroSilicon MS2130"
                0x2131 -> "MacroSilicon MS2131"
                else -> "MacroSilicon (Unknown)"
            }

            0xeb1a -> when (pid) {
                0x2860 -> "Empia EM2860"
                0x2870 -> "Empia EM2870"
                0x2820 -> "Empia EM2820"
                else -> "Empia EM28xx"
            }

            0x05e1 -> "Syntek"
            0x1b71 -> when (pid) {
                0x3002 -> "Fushicai USBTV007"
                0x3003 -> "Fushicai USBTV007A"
                else -> "Fushicai"
            }

            0x046d -> "Logitech"
            0x0c45 -> "Sonix"
            0x32e4, 0x322e -> "Sonix WebCam"
            0x1bcf -> "Sunplus"
            0x1871 -> "AVEO"
            0x0416 -> "Winbond"
            0x090c -> "Silicon Motion"
            0x13d3 -> "IMC Networks"
            0x058f -> "Alcor Micro"
            0x0909 -> "Audio-Technica"
            0x0bda -> "Realtek"
            else -> "Unknown"
        }
    }

    /**
     * 检查是否是 UVC (USB Video Class) 设备
     */
    private fun isUvcDevice(device: UsbDevice): Boolean {
        // 遍历所有接口检查是否是视频类
        for (i in 0 until device.interfaceCount) {
            val usbInterface = device.getInterface(i)
            // USB Video Class = 14 (0x0E)
            if (usbInterface.interfaceClass == 14) {
                android.util.Log.d("UsbCapturePlugin", "  ✓ 发现 UVC 接口 (class=14)")
                return true
            }
        }
        return false
    }

    /**
     * 注册 USB 广播接收器
     */
    private fun registerUsbReceiver() {
        usbReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.action) {
                    UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                        val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                        }
                        device?.let { handleDeviceAttached(it) }
                    }

                    UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                        val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                        }
                        device?.let { handleDeviceDetached(it) }
                    }

                    ACTION_USB_PERMISSION -> {
                        val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                        }
                        val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                        android.util.Log.d("UsbCapturePlugin", "USB 权限结果: $granted, 设备: ${device?.productName}")

                        if (granted && device != null && isCaptureCard(device)) {
                            connectedDevice = device
                            eventSink?.success(
                                mapOf(
                                    "type" to "permissionGranted",
                                    "device" to deviceToMap(device)
                                )
                            )
                        } else if (!granted && device != null) {
                            eventSink?.success(
                                mapOf(
                                    "type" to "permissionDenied",
                                    "device" to deviceToMap(device)
                                )
                            )
                        }
                    }
                }
            }
        }

        val filter = IntentFilter().apply {
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            addAction(ACTION_USB_PERMISSION)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(usbReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            context.registerReceiver(usbReceiver, filter)
        }
    }

    /**
     * 处理设备插入
     */
    private fun handleDeviceAttached(device: UsbDevice) {
        val vid = device.vendorId
        val pid = device.productId

        // 检测：VID/PID 匹配 或 UVC 设备 或 产品名关键词
        if (isKnownCaptureCard(vid, pid) || isUvcDevice(device) || isCaptureCardByName(device)) {
            connectedDevice = device

            // 检查是否有权限，如果没有则请求
            if (!usbManager.hasPermission(device)) {
                requestUsbPermission(device)
            }

            android.util.Log.d("UsbCapturePlugin", "发送 attached 事件到 Flutter: ${device.productName}")
            eventSink?.success(
                mapOf(
                    "type" to "attached",
                    "device" to deviceToMap(device)
                )
            )
        }
    }

    /**
     * 请求 USB 权限
     */
    private fun requestUsbPermission(device: UsbDevice) {
        try {
            android.util.Log.d(
                "UsbCapturePlugin",
                "正在请求 USB 权限，设备: ${device.productName}, deviceId: ${device.deviceId}"
            )

            // 创建显式 Intent 确保广播能正确接收
            val intent = Intent(ACTION_USB_PERMISSION).apply {
                setPackage(context.packageName)
                // 添加设备信息到 Intent 以便在接收器中识别
                putExtra(UsbManager.EXTRA_DEVICE, device)
            }

            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_MUTABLE
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            } else {
                android.app.PendingIntent.FLAG_UPDATE_CURRENT
            }

            val permissionIntent = android.app.PendingIntent.getBroadcast(
                context,
                device.deviceId, // 使用 deviceId 作为 requestCode 区分不同设备
                intent,
                flags
            )

            android.util.Log.d("UsbCapturePlugin", "发送权限请求...")
            usbManager.requestPermission(device, permissionIntent)
            android.util.Log.d("UsbCapturePlugin", "权限请求已发送")
        } catch (e: Exception) {
            android.util.Log.e("UsbCapturePlugin", "请求 USB 权限失败: ${e.message}", e)
        }
    }

    /**
     * 处理设备拔出
     */
    private fun handleDeviceDetached(device: UsbDevice) {
        if (connectedDevice?.deviceId == device.deviceId) {
            connectedDevice = null
            eventSink?.success(
                mapOf(
                    "type" to "detached",
                    "device" to deviceToMap(device)
                )
            )
        }
    }

    /**
     * 检查设备是否是视频采集卡
     */
    private fun isCaptureCard(device: UsbDevice): Boolean {
        val vid = device.vendorId
        val pid = device.productId
        val productName = device.productName ?: "Unknown"

        android.util.Log.d(
            "UsbCapturePlugin",
            "检查设备: $productName (VID: 0x${vid.toString(16)}, PID: 0x${pid.toString(16)})"
        )

        // 检查 VID/PID
        val knownPids = CAPTURE_CARD_SIGNATURES[vid]
        if (knownPids != null) {
            if (knownPids.isEmpty() || knownPids.contains(pid)) {
                android.util.Log.d("UsbCapturePlugin", "✓ VID/PID 匹配: 0x${vid.toString(16)}:0x${pid.toString(16)}")
                return true
            }
        }

        // 检查产品名称关键词
        val productNameLower = productName.lowercase()
        val captureKeywords = listOf(
            "capture", "video", "camera", "hdmi", "采集卡", "摄像头", "webcam", "uvc"
        )
        for (keyword in captureKeywords) {
            if (productNameLower.contains(keyword)) {
                android.util.Log.d("UsbCapturePlugin", "✓ 产品名称匹配关键词 '$keyword': $productName")
                return true
            }
        }

        return false
    }

    /**
     * 将 UsbDevice 转换为 Map
     */
    private fun deviceToMap(device: UsbDevice): Map<String, Any?> {
        return mapOf(
            "vid" to device.vendorId,
            "pid" to device.productId,
            "productName" to device.productName,
            "manufacturerName" to device.manufacturerName,
            "serialNumber" to device.serialNumber
        )
    }

    // ==================== MethodCallHandler ====================

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: MethodChannel.Result) {
        when (call.method) {
            "isCaptureCardConnected" -> {
                result.success(connectedDevice != null)
            }

            "getConnectedDevice" -> {
                connectedDevice?.let {
                    result.success(deviceToMap(it))
                } ?: result.success(null)
            }

            "getVideoDevicePath" -> {
                // 假设第一个 UVC 设备对应 video0
                // 实际项目中可以通过其他方式确定
                result.success("/dev/video0")
            }

            "getAllUsbDevices" -> {
                // 返回所有 USB 设备信息（用于调试）
                val devices = usbManager.deviceList.map { (_, device) ->
                    // 检查接口类别
                    var hasVideoInterface = false
                    var hasAudioInterface = false
                    val interfaceClasses = mutableListOf<Int>()

                    for (i in 0 until device.interfaceCount) {
                        val usbInterface = device.getInterface(i)
                        val cls = usbInterface.interfaceClass
                        interfaceClasses.add(cls)
                        if (cls == 14) hasVideoInterface = true  // Video
                        if (cls == 1) hasAudioInterface = true   // Audio
                    }

                    // 识别芯片型号
                    val chipName = identifyChip(device.vendorId, device.productId)

                    mapOf(
                        "vid" to device.vendorId,
                        "pid" to device.productId,
                        "productName" to device.productName,
                        "manufacturerName" to device.manufacturerName,
                        "deviceId" to device.deviceId,
                        "deviceClass" to device.deviceClass,
                        "deviceSubclass" to device.deviceSubclass,
                        "deviceProtocol" to device.deviceProtocol,
                        "interfaceCount" to device.interfaceCount,
                        "interfaceClasses" to interfaceClasses,
                        "hasVideoInterface" to hasVideoInterface,
                        "hasAudioInterface" to hasAudioInterface,
                        "chipName" to chipName,
                        "isCaptureCard" to (isKnownCaptureCard(
                            device.vendorId,
                            device.productId
                        ) || isUvcDevice(device) || isCaptureCardByName(device)),
                        "hasPermission" to usbManager.hasPermission(device)
                    )
                }
                result.success(devices)
            }

            "requestUsbPermission" -> {
                // 请求 USB 权限
                val deviceId = call.argument<Int>("deviceId")
                if (deviceId != null) {
                    val device = usbManager.deviceList.values.find { it.deviceId == deviceId }
                    if (device != null) {
                        if (usbManager.hasPermission(device)) {
                            result.success(true)
                        } else {
                            requestUsbPermission(device)
                            result.success(false) // 权限请求已发送，但尚未获得
                        }
                    } else {
                        result.error("DEVICE_NOT_FOUND", "找不到指定的 USB 设备", null)
                    }
                } else {
                    // 如果没有指定 deviceId，请求第一个采集卡的权限
                    connectedDevice?.let { device ->
                        if (usbManager.hasPermission(device)) {
                            result.success(true)
                        } else {
                            requestUsbPermission(device)
                            result.success(false)
                        }
                    } ?: result.error("NO_DEVICE", "没有连接的采集卡设备", null)
                }
            }

            "hasUsbPermission" -> {
                // 检查是否有 USB 权限
                connectedDevice?.let { device ->
                    result.success(usbManager.hasPermission(device))
                } ?: result.success(false)
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    // ==================== EventChannel.StreamHandler ====================

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        android.util.Log.d("UsbCapturePlugin", "Flutter 开始监听事件, 当前设备: ${connectedDevice?.productName}")

        // 发送当前已连接的设备
        connectedDevice?.let { device ->
            android.util.Log.d("UsbCapturePlugin", "发送已连接设备到 Flutter: ${device.productName}")
            events?.success(
                mapOf(
                    "type" to "attached",
                    "device" to deviceToMap(device)
                )
            )
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    /**
     * 清理资源
     */
    fun dispose() {
        usbReceiver?.let {
            context.unregisterReceiver(it)
            usbReceiver = null
        }
        eventSink = null
    }
}
