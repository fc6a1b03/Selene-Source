package com.selene

import android.content.Intent
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.selene.usb.UsbCapturePlugin

/**
 * MainActivity
 * 
 * 应用主入口，注册 USB 采集卡插件
 * 处理 USB 设备插入时启动应用的情况
 */
class MainActivity : FlutterActivity() {

    private var usbCapturePlugin: UsbCapturePlugin? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // 处理通过 USB 设备启动的情况
        handleUsbIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        
        // 处理新的 USB 设备 Intent
        handleUsbIntent(intent)
    }

    /**
     * 处理 USB 相关的 Intent
     */
    private fun handleUsbIntent(intent: Intent?) {
        if (intent?.action == UsbManager.ACTION_USB_DEVICE_ATTACHED) {
            val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
            }
            device?.let {
                // 设备已连接，插件会处理广播事件
                android.util.Log.d("MainActivity", "USB 设备通过 Intent 连接: ${it.productName}")
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // 注册 USB 采集卡插件
        usbCapturePlugin = UsbCapturePlugin.registerWith(flutterEngine, this)
    }

    override fun onDestroy() {
        usbCapturePlugin?.dispose()
        super.onDestroy()
    }
}
