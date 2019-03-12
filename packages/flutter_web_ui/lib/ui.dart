// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

export 'src/canvas.dart';
export 'src/compositing.dart';
export 'src/engine.dart';
export 'src/geometry.dart';
export 'src/hash_codes.dart';
export 'src/initialization.dart';
export 'src/lerp.dart';
export 'src/natives.dart';
export 'src/painting.dart' hide PaintData;
export 'src/pointer.dart';
export 'src/pointer_binding.dart';
export 'src/semantics.dart';
export 'src/browser_routing/strategies.dart';
export 'src/text.dart';
export 'src/tile_mode.dart';
export 'src/window.dart';

/// Provides a compile time constant to customize flutter framework and other
/// users of ui engine for web runtime.
const bool isWeb = true;

/// Web specific SMI. Used by bitfield. The 0x3FFFFFFFFFFFFFFF used on VM
/// is not supported on Web platform.
const int kMaxUnsignedSMI = -1;
