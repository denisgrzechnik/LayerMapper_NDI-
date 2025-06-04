//
//  NDIEnvironment.swift
//  LayerMapper
//
//  Created by Denis Grzechnik on 02/06/2025.
//

import Foundation

/// Jeden współdzielony finder i globalne `NDIlib_initialize`/`destroy`
final class NDIEnvironment {
    static let shared = NDIEnvironment()          // lazy-thread-safe

    /// Finder, z którego korzystają wszystkie ekrany
    let finder: OpaquePointer

    private init() {
        // AppDelegate już sprawdził wynik zwrotu, tu zakładamy, że działa
        guard let f = NDIlib_find_create_v2(nil) else {
            fatalError("NDIlib_find_create_v2() failed")
        }
        finder = f
    }

    deinit {                                      // praktycznie nigdy
        NDIlib_find_destroy(finder)
        NDIlib_destroy()
    }
}
