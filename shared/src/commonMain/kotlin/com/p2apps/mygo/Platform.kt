package com.p2apps.mygo

interface Platform {
    val name: String
}

expect fun getPlatform(): Platform