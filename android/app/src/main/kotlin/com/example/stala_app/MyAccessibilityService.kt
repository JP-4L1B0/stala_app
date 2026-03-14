package com.example.stala_app

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent

class MyAccessibilityService : AccessibilityService() {

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Handle accessibility events here if needed later.
    }

    override fun onInterrupt() {
        // Handle interruption here if needed later.
    }
}