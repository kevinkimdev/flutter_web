// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

import 'canvas.dart';
import 'engine_canvas.dart';
import 'geometry.dart';
import 'painting.dart';
import 'shadow.dart';
import 'text.dart';

import 'util.dart';

/// Enable this to print every command applied by a canvas.
const bool _debugDumpPaintCommands = false;

/// Records canvas commands to be applied to a [EngineCanvas].
///
/// See [Canvas] for docs for these methods.
class RecordingCanvas {
  /// Maximum paintable bounds for this canvas.
  final _PaintBounds _paintBounds;
  final _commands = <PaintCommand>[];

  RecordingCanvas(Rect bounds) : this._paintBounds = _PaintBounds(bounds);

  /// Whether this canvas is doing arbitrary paint operations not expressible
  /// via DOM elements.
  bool get hasArbitraryPaint => _hasArbitraryPaint;
  bool _hasArbitraryPaint = false;

  /// Whether this canvas contain drawing operations.
  ///
  /// Some pictures are created but only contain operations that do not result
  /// in any pixels on the screen. For example, they will only contain saves,
  /// restores, and translates. This happens when a parent [RenderObject]
  /// prepares the canvas for its children to paint to, but the child ends up
  /// not painting anything, such as when an empty [SizedBox] is used to add a
  /// margin between two widgets.
  bool get didDraw => _didDraw;
  bool _didDraw = false;

  /// Computes paint bounds based on estimated [bounds] and transforms.
  Rect computePaintBounds() {
    return _paintBounds.computeBounds();
  }

  void apply(EngineCanvas engineCanvas, {bool clearFirst: true}) {
    if (_debugDumpPaintCommands) {
      print('--- Applying RecordingCanvas to ${engineCanvas.runtimeType} '
          'with bounds $_paintBounds');
      if (clearFirst) {
        engineCanvas.clear();
      }
      for (var i = 0; i < _commands.length; i++) {
        var command = _commands[i];
        print('  - $command');
        command.apply(engineCanvas);
      }
      print('--- End of command stream');
    } else {
      if (clearFirst) {
        engineCanvas.clear();
      }
      for (var i = 0; i < _commands.length; i++) {
        _commands[i].apply(engineCanvas);
      }
    }
  }

  void save() {
    _paintBounds.saveTransformsAndClip();
    _commands.add(const PaintSave());
    saveCount++;
  }

  void saveLayerWithoutBounds(Paint paint) {
    _hasArbitraryPaint = true;
    // TODO(het): Implement this correctly using another canvas.
    _commands.add(const PaintSave());
    _paintBounds.saveTransformsAndClip();
    saveCount++;
  }

  void saveLayer(Rect bounds, Paint paint) {
    _hasArbitraryPaint = true;
    // TODO(het): Implement this correctly using another canvas.
    _commands.add(const PaintSave());
    _paintBounds.saveTransformsAndClip();
    saveCount++;
  }

  void restore() {
    _paintBounds.restoreTransformsAndClip();
    if (_commands.isNotEmpty && _commands.last is PaintSave) {
      // A restore followed a save without any drawing operations in between.
      // This means that the save didn't have any effect on drawing operations
      // and can be omitted. This makes our communication with the canvas less
      // chatty.
      _commands.removeLast();
    } else {
      _commands.add(const PaintRestore());
    }
    saveCount--;
  }

  void translate(double dx, double dy) {
    _paintBounds.translate(dx, dy);
    _commands.add(new PaintTranslate(dx, dy));
  }

  void scale(double sx, double sy) {
    _paintBounds.scale(sx, sy);
    _commands.add(new PaintScale(sx, sy));
  }

  void rotate(double radians) {
    _paintBounds.rotateZ(radians);
    _commands.add(new PaintRotate(radians));
  }

  void transform(Float64List matrix4) {
    _paintBounds.transform(matrix4);
    _commands.add(new PaintTransform(matrix4));
  }

  void skew(double sx, double sy) {
    _hasArbitraryPaint = true;
    _paintBounds.skew(sx, sy);
    _commands.add(new PaintSkew(sx, sy));
  }

  void clipRect(Rect rect) {
    _paintBounds.clipRect(rect);
    _hasArbitraryPaint = true;
    _commands.add(new PaintClipRect(rect));
  }

  void clipRRect(RRect rrect) {
    _paintBounds.clipRect(rrect.outerRect);
    _hasArbitraryPaint = true;
    _commands.add(new PaintClipRRect(rrect));
  }

  void clipPath(Path path) {
    _paintBounds.clipRect(path.getBounds());
    _hasArbitraryPaint = true;
    _commands.add(new PaintClipPath(path));
  }

  void drawColor(Color color, BlendMode blendMode) {
    _hasArbitraryPaint = true;
    _didDraw = true;
    _paintBounds.grow(_paintBounds.maxPaintBounds);
    _commands.add(new PaintDrawColor(color, blendMode));
  }

  void drawLine(Offset p1, Offset p2, Paint paint) {
    var strokeWidth = paint.strokeWidth == null ? 0 : paint.strokeWidth;
    _paintBounds.growLTRB(
        math.min(p1.dx, p2.dx) - strokeWidth,
        math.min(p1.dy, p2.dy) - strokeWidth,
        math.max(p1.dx, p2.dx) + strokeWidth,
        math.max(p1.dy, p2.dy) + strokeWidth);
    _hasArbitraryPaint = true;
    _didDraw = true;
    _commands.add(new PaintDrawLine(p1, p2, paint));
  }

  void drawPaint(Paint paint) {
    _hasArbitraryPaint = true;
    _didDraw = true;
    _paintBounds.grow(_paintBounds.maxPaintBounds);
    _commands.add(new PaintDrawPaint(paint));
  }

  void drawRect(Rect rect, Paint paint) {
    if (paint.shader != null) {
      _hasArbitraryPaint = true;
    }
    _didDraw = true;
    if (paint.strokeWidth != null && paint.strokeWidth > 1.0) {
      _paintBounds.grow(rect.inflate(paint.strokeWidth));
    } else {
      _paintBounds.grow(rect);
    }
    _commands.add(new PaintDrawRect(rect, paint));
  }

  void drawRRect(RRect rrect, Paint paint) {
    _hasArbitraryPaint = true;
    _didDraw = true;
    var strokeWidth = paint.strokeWidth == null ? 0 : paint.strokeWidth;
    var left = math.min(rrect.left, rrect.right) - strokeWidth;
    var right = math.max(rrect.left, rrect.right) + strokeWidth;
    var top = math.min(rrect.top, rrect.bottom) - strokeWidth;
    var bottom = math.max(rrect.top, rrect.bottom) + strokeWidth;
    _paintBounds.growLTRB(left, top, right, bottom);
    _commands.add(new PaintDrawRRect(rrect, paint));
  }

  void drawDRRect(RRect outer, RRect inner, Paint paint) {
    _hasArbitraryPaint = true;
    _didDraw = true;
    var strokeWidth = paint.strokeWidth == null ? 0 : paint.strokeWidth;
    _paintBounds.growLTRB(outer.left - strokeWidth, outer.top - strokeWidth,
        outer.right + strokeWidth, outer.bottom + strokeWidth);
    _commands.add(new PaintDrawDRRect(outer, inner, paint));
  }

  void drawOval(Rect rect, Paint paint) {
    _hasArbitraryPaint = true;
    _didDraw = true;
    if (paint.strokeWidth != null && paint.strokeWidth > 1.0) {
      _paintBounds.grow(rect.inflate(paint.strokeWidth));
    } else {
      _paintBounds.grow(rect);
    }
    _commands.add(new PaintDrawOval(rect, paint));
  }

  void drawCircle(Offset c, double radius, Paint paint) {
    _hasArbitraryPaint = true;
    _didDraw = true;
    var strokeWidth = paint.strokeWidth == null ? 0 : paint.strokeWidth;
    _paintBounds.growLTRB(
        c.dx - radius - strokeWidth,
        c.dy - radius - strokeWidth,
        c.dx + radius + strokeWidth,
        c.dy + radius + strokeWidth);
    _commands.add(new PaintDrawCircle(c, radius, paint));
  }

  void drawPath(Path path, Paint paint) {
    _hasArbitraryPaint = true;
    _didDraw = true;
    Rect pathBounds = path.getBounds();
    if (paint.strokeWidth != null && paint.strokeWidth > 1.0) {
      pathBounds = pathBounds.inflate(paint.strokeWidth);
    }
    _paintBounds.grow(pathBounds);
    _commands.add(new PaintDrawPath(path, paint));
  }

  void drawImage(Image image, Offset offset, Paint paint) {
    _hasArbitraryPaint = true;
    _didDraw = true;
    var left = offset.dx;
    var top = offset.dy;
    _paintBounds.growLTRB(left, top, left + image.width, top + image.height);
    _commands.add(new PaintDrawImage(image, offset, paint));
  }

  void drawImageRect(Image image, Rect src, Rect dst, Paint paint) {
    _hasArbitraryPaint = true;
    _didDraw = true;
    _paintBounds.grow(dst);
    _commands.add(new PaintDrawImageRect(image, src, dst, paint));
  }

  void drawParagraph(Paragraph paragraph, Offset offset) {
    _didDraw = true;
    var left = offset.dx;
    var top = offset.dy;
    _paintBounds.growLTRB(
        left, top, left + paragraph.width, top + paragraph.height);
    _commands.add(new PaintDrawParagraph(paragraph, offset));
  }

  void drawShadow(
      Path path, Color color, double elevation, bool transparentOccluder) {
    _hasArbitraryPaint = true;
    _didDraw = true;
    Rect shadowRect =
        ElevationShadow.computeShadowRect(path.getBounds(), elevation);
    _paintBounds.grow(shadowRect);
    _commands
        .add(new PaintDrawShadow(path, color, elevation, transparentOccluder));
  }

  int saveCount = 1;

  /// Prints the commands recorded by this canvas to the console.
  void debugDumpCommands() {
    print('/' * 40 + ' CANVAS COMMANDS ' + '/' * 40);
    for (final command in _commands) {
      print(command);
    }
    print('/' * 37 + ' END OF CANVAS COMMANDS ' + '/' * 36);
  }
}

abstract class PaintCommand {
  const PaintCommand();

  void apply(EngineCanvas canvas);

  void serializeToCssPaint(List<List> serializedCommands);
}

class PaintSave extends PaintCommand {
  const PaintSave();

  @override
  void apply(EngineCanvas canvas) {
    canvas.save();
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'Save';
    } else {
      return super.toString();
    }
  }

  void serializeToCssPaint(List<List> serializedCommands) {
    serializedCommands.add(const [1]);
  }
}

class PaintRestore extends PaintCommand {
  const PaintRestore();

  @override
  void apply(EngineCanvas canvas) {
    canvas.restore();
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'Restore';
    } else {
      return super.toString();
    }
  }

  void serializeToCssPaint(List<List> serializedCommands) {
    serializedCommands.add(const [2]);
  }
}

class PaintTranslate extends PaintCommand {
  final double dx;
  final double dy;

  PaintTranslate(this.dx, this.dy);

  @override
  void apply(EngineCanvas canvas) {
    canvas.translate(dx, dy);
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'Translate($dx, $dy)';
    } else {
      return super.toString();
    }
  }

  void serializeToCssPaint(List<List> serializedCommands) {
    serializedCommands.add([3, dx, dy]);
  }
}

class PaintScale extends PaintCommand {
  final double sx;
  final double sy;

  PaintScale(this.sx, this.sy);

  @override
  void apply(EngineCanvas canvas) {
    canvas.scale(sx, sy);
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'Scale($sx, $sy)';
    } else {
      return super.toString();
    }
  }

  void serializeToCssPaint(List<List> serializedCommands) {
    serializedCommands.add([4, sx, sy]);
  }
}

class PaintRotate extends PaintCommand {
  final double radians;

  PaintRotate(this.radians);

  @override
  void apply(EngineCanvas canvas) {
    canvas.rotate(radians);
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'Rotate($radians)';
    } else {
      return super.toString();
    }
  }

  void serializeToCssPaint(List<List> serializedCommands) {
    serializedCommands.add([5, radians]);
  }
}

class PaintTransform extends PaintCommand {
  final Float64List matrix4;

  PaintTransform(this.matrix4);

  @override
  void apply(EngineCanvas canvas) {
    canvas.transform(matrix4);
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'Transform(${matrix4.join(', ')})';
    } else {
      return super.toString();
    }
  }

  void serializeToCssPaint(List<List> serializedCommands) {
    serializedCommands.add([6]..addAll(matrix4));
  }
}

class PaintSkew extends PaintCommand {
  final double sx;
  final double sy;

  PaintSkew(this.sx, this.sy);

  @override
  void apply(EngineCanvas canvas) {
    canvas.skew(sx, sy);
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'Skew($sx, $sy)';
    } else {
      return super.toString();
    }
  }

  void serializeToCssPaint(List<List> serializedCommands) {
    serializedCommands.add([7, sx, sy]);
  }
}

class PaintClipRect extends PaintCommand {
  final Rect rect;

  PaintClipRect(this.rect);

  @override
  void apply(EngineCanvas canvas) {
    canvas.clipRect(rect);
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'ClipRect($rect)';
    } else {
      return super.toString();
    }
  }

  void serializeToCssPaint(List<List> serializedCommands) {
    serializedCommands.add([8, _serializeRectToCssPaint(rect)]);
  }
}

class PaintClipRRect extends PaintCommand {
  final RRect rrect;

  PaintClipRRect(this.rrect);

  @override
  void apply(EngineCanvas canvas) {
    canvas.clipRRect(rrect);
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'ClipRRect($rrect)';
    } else {
      return super.toString();
    }
  }

  void serializeToCssPaint(List<List> serializedCommands) {
    serializedCommands.add([
      9,
      _serializeRRectToCssPaint(rrect),
    ]);
  }
}

class PaintClipPath extends PaintCommand {
  final Path path;

  PaintClipPath(this.path);

  @override
  void apply(EngineCanvas canvas) {
    canvas.clipPath(path);
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'ClipPath($path)';
    } else {
      return super.toString();
    }
  }

  void serializeToCssPaint(List<List> serializedCommands) {
    serializedCommands.add([10, path.webOnlySerializeToCssPaint()]);
  }
}

class PaintDrawColor extends PaintCommand {
  final Color color;
  final BlendMode blendMode;

  PaintDrawColor(this.color, this.blendMode);

  @override
  void apply(EngineCanvas canvas) {
    canvas.drawColor(color, blendMode);
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'DrawColor($color, $blendMode)';
    } else {
      return super.toString();
    }
  }

  void serializeToCssPaint(List<List> serializedCommands) {
    serializedCommands.add([11, color.toCssString(), blendMode.index]);
  }
}

class PaintDrawLine extends PaintCommand {
  final Offset p1;
  final Offset p2;
  final Paint paint;

  PaintDrawLine(this.p1, this.p2, this.paint);

  @override
  void apply(EngineCanvas canvas) {
    canvas.drawLine(p1, p2, paint);
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'DrawLine($p1, $p2, $paint)';
    } else {
      return super.toString();
    }
  }

  void serializeToCssPaint(List<List> serializedCommands) {
    serializedCommands.add(
        [12, p1.dx, p1.dy, p2.dx, p2.dy, _serializePaintToCssPaint(paint)]);
  }
}

class PaintDrawPaint extends PaintCommand {
  final Paint paint;

  PaintDrawPaint(this.paint);

  @override
  void apply(EngineCanvas canvas) {
    canvas.drawPaint(paint);
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'DrawPaint($paint)';
    } else {
      return super.toString();
    }
  }

  void serializeToCssPaint(List<List> serializedCommands) {
    serializedCommands.add([13, _serializePaintToCssPaint(paint)]);
  }
}

class PaintDrawRect extends PaintCommand {
  final Rect rect;
  final Paint paint;

  PaintDrawRect(this.rect, this.paint);

  @override
  void apply(EngineCanvas canvas) {
    canvas.drawRect(rect, paint);
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'DrawRect($rect, $paint)';
    } else {
      return super.toString();
    }
  }

  void serializeToCssPaint(List<List> serializedCommands) {
    serializedCommands.add(
        [14, _serializeRectToCssPaint(rect), _serializePaintToCssPaint(paint)]);
  }
}

class PaintDrawRRect extends PaintCommand {
  final RRect rrect;
  final Paint paint;

  PaintDrawRRect(this.rrect, this.paint);

  @override
  void apply(EngineCanvas canvas) {
    canvas.drawRRect(rrect, paint);
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'DrawRRect($rrect, $paint)';
    } else {
      return super.toString();
    }
  }

  void serializeToCssPaint(List<List> serializedCommands) {
    serializedCommands.add([
      15,
      _serializeRRectToCssPaint(rrect),
      _serializePaintToCssPaint(paint),
    ]);
  }
}

class PaintDrawDRRect extends PaintCommand {
  final RRect outer;
  final RRect inner;
  final Paint paint;

  PaintDrawDRRect(this.outer, this.inner, this.paint);

  @override
  void apply(EngineCanvas canvas) {
    canvas.drawDRRect(outer, inner, paint);
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'DrawDRRect($outer, $inner, $paint)';
    } else {
      return super.toString();
    }
  }

  void serializeToCssPaint(List<List> serializedCommands) {
    serializedCommands.add([
      16,
      _serializeRRectToCssPaint(outer),
      _serializeRRectToCssPaint(inner),
      _serializePaintToCssPaint(paint),
    ]);
  }
}

class PaintDrawOval extends PaintCommand {
  final Rect rect;
  final Paint paint;

  PaintDrawOval(this.rect, this.paint);

  @override
  void apply(EngineCanvas canvas) {
    canvas.drawOval(rect, paint);
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'DrawOval($rect, $paint)';
    } else {
      return super.toString();
    }
  }

  void serializeToCssPaint(List<List> serializedCommands) {
    serializedCommands.add([
      17,
      _serializeRectToCssPaint(rect),
      _serializePaintToCssPaint(paint),
    ]);
  }
}

class PaintDrawCircle extends PaintCommand {
  final Offset c;
  final double radius;
  final Paint paint;

  PaintDrawCircle(this.c, this.radius, this.paint);

  @override
  void apply(EngineCanvas canvas) {
    canvas.drawCircle(c, radius, paint);
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'DrawCircle($c, $radius, $paint)';
    } else {
      return super.toString();
    }
  }

  void serializeToCssPaint(List<List> serializedCommands) {
    serializedCommands.add([
      18,
      c.dx,
      c.dy,
      radius,
      _serializePaintToCssPaint(paint),
    ]);
  }
}

class PaintDrawPath extends PaintCommand {
  final Path path;
  final Paint paint;

  PaintDrawPath(this.path, this.paint);

  @override
  void apply(EngineCanvas canvas) {
    canvas.drawPath(path, paint);
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'DrawPath($path, $paint)';
    } else {
      return super.toString();
    }
  }

  void serializeToCssPaint(List<List> serializedCommands) {
    serializedCommands.add([
      19,
      path.webOnlySerializeToCssPaint(),
      _serializePaintToCssPaint(paint),
    ]);
  }
}

class PaintDrawShadow extends PaintCommand {
  PaintDrawShadow(
      this.path, this.color, this.elevation, this.transparentOccluder);

  final Path path;
  final Color color;
  final double elevation;
  final bool transparentOccluder;

  @override
  void apply(EngineCanvas canvas) {
    canvas.drawShadow(path, color, elevation, transparentOccluder);
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'DrawShadow($path, $color, $elevation, $transparentOccluder)';
    } else {
      return super.toString();
    }
  }

  void serializeToCssPaint(List<List> serializedCommands) {
    serializedCommands.add([
      20,
      path.webOnlySerializeToCssPaint(),
      [
        color.alpha,
        color.red,
        color.green,
        color.blue,
      ],
      elevation,
      transparentOccluder,
    ]);
  }
}

class PaintDrawImage extends PaintCommand {
  final Image image;
  final Offset offset;
  final Paint paint;

  PaintDrawImage(this.image, this.offset, this.paint);

  @override
  void apply(EngineCanvas canvas) {
    canvas.drawImage(image, offset, paint);
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'DrawImage($image, $offset, $paint)';
    } else {
      return super.toString();
    }
  }

  void serializeToCssPaint(List<List> serializedCommands) {
    if (assertionsEnabled) {
      throw UnsupportedError('drawImage not serializable');
    }
  }
}

class PaintDrawImageRect extends PaintCommand {
  final Image image;
  final Rect src;
  final Rect dst;
  final Paint paint;

  PaintDrawImageRect(this.image, this.src, this.dst, this.paint);

  @override
  void apply(EngineCanvas canvas) {
    canvas.drawImageRect(image, src, dst, paint);
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'DrawImageRect($image, $src, $dst, $paint)';
    } else {
      return super.toString();
    }
  }

  void serializeToCssPaint(List<List> serializedCommands) {
    if (assertionsEnabled) {
      throw UnsupportedError('drawImageRect not serializable');
    }
  }
}

class PaintDrawParagraph extends PaintCommand {
  final Paragraph paragraph;
  final Offset offset;

  PaintDrawParagraph(this.paragraph, this.offset);

  @override
  void apply(EngineCanvas canvas) {
    canvas.drawParagraph(paragraph, offset);
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'DrawParagraph(${paragraph.webOnlyGetPlainText()}, $offset)';
    } else {
      return super.toString();
    }
  }

  void serializeToCssPaint(List<List> serializedCommands) {
    if (assertionsEnabled) {
      throw UnsupportedError('drawParagraph not serializable');
    }
  }
}

List _serializePaintToCssPaint(Paint paint) {
  return [
    paint.blendMode?.index,
    paint.style?.index,
    paint.strokeWidth,
    paint.strokeCap?.index,
    paint.isAntiAlias,
    paint.color.toCssString(),
    paint.shader?.webOnlySerializeToCssPaint(),
    paint.maskFilter?.webOnlySerializeToCssPaint(),
    paint.filterQuality?.index,
    paint.colorFilter?.webOnlySerializeToCssPaint(),
  ];
}

List _serializeRectToCssPaint(Rect rect) {
  return [
    rect.left,
    rect.top,
    rect.right,
    rect.bottom,
  ];
}

List _serializeRRectToCssPaint(RRect rrect) {
  return [
    rrect.left,
    rrect.top,
    rrect.right,
    rrect.bottom,
    rrect.tlRadiusX,
    rrect.tlRadiusY,
    rrect.trRadiusX,
    rrect.trRadiusY,
    rrect.brRadiusX,
    rrect.brRadiusY,
    rrect.blRadiusX,
    rrect.blRadiusY,
  ];
}

class Subpath {
  double startX = 0.0;
  double startY = 0.0;
  double currentX = 0.0;
  double currentY = 0.0;

  final List<PathCommand> commands;

  Subpath(this.startX, this.startY) : commands = <PathCommand>[];

  Subpath shift(Offset offset) {
    final result = Subpath(startX + offset.dx, startY + offset.dy)
      ..currentX = currentX + offset.dx
      ..currentY = currentY + offset.dy;

    for (final command in commands) {
      result.commands.add(command.shifted(offset));
    }

    return result;
  }

  List serializeToCssPaint() {
    final List serialization = [];
    for (int i = 0; i < commands.length; i++) {
      serialization.add(commands[i].serializeToCssPaint());
    }
    return serialization;
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'Subpath(${commands.join(', ')})';
    } else {
      return super.toString();
    }
  }
}

/// ! Houdini implementation relies on indices here. Keep in sync.
class PathCommandTypes {
  static const moveTo = 0;
  static const lineTo = 1;
  static const ellipse = 2;
  static const close = 3;
  static const quadraticCurveTo = 4;
  static const bezierCurveTo = 5;
  static const rect = 6;
  static const rRect = 7;
}

abstract class PathCommand {
  final int type;
  const PathCommand(this.type);

  PathCommand shifted(Offset offset);

  List serializeToCssPaint();
}

class MoveTo extends PathCommand {
  final double x;
  final double y;

  const MoveTo(this.x, this.y) : super(PathCommandTypes.moveTo);

  @override
  MoveTo shifted(Offset offset) {
    return new MoveTo(x + offset.dx, y + offset.dy);
  }

  @override
  List serializeToCssPaint() {
    return [1, x, y];
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'MoveTo($x, $y)';
    } else {
      return super.toString();
    }
  }
}

class LineTo extends PathCommand {
  final double x;
  final double y;

  const LineTo(this.x, this.y) : super(PathCommandTypes.lineTo);

  @override
  LineTo shifted(Offset offset) {
    return new LineTo(x + offset.dx, y + offset.dy);
  }

  @override
  List serializeToCssPaint() {
    return [2, x, y];
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'LineTo($x, $y)';
    } else {
      return super.toString();
    }
  }
}

class Ellipse extends PathCommand {
  final double x;
  final double y;
  final double radiusX;
  final double radiusY;
  final double rotation;
  final double startAngle;
  final double endAngle;
  final bool anticlockwise;

  const Ellipse(this.x, this.y, this.radiusX, this.radiusY, this.rotation,
      this.startAngle, this.endAngle, this.anticlockwise)
      : super(PathCommandTypes.ellipse);

  @override
  Ellipse shifted(Offset offset) {
    return new Ellipse(x + offset.dx, y + offset.dy, radiusX, radiusY, rotation,
        startAngle, endAngle, anticlockwise);
  }

  @override
  List serializeToCssPaint() {
    return [
      3,
      x,
      y,
      radiusX,
      radiusY,
      rotation,
      startAngle,
      endAngle,
      anticlockwise,
    ];
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'Ellipse($x, $y, $radiusX, $radiusY)';
    } else {
      return super.toString();
    }
  }
}

class QuadraticCurveTo extends PathCommand {
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  const QuadraticCurveTo(this.x1, this.y1, this.x2, this.y2)
      : super(PathCommandTypes.quadraticCurveTo);

  @override
  QuadraticCurveTo shifted(Offset offset) {
    return new QuadraticCurveTo(
        x1 + offset.dx, y1 + offset.dy, x2 + offset.dx, y2 + offset.dy);
  }

  @override
  List serializeToCssPaint() {
    return [4, x1, y1, x2, y2];
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'QuadraticCurveTo($x1, $y1, $x2, $y2)';
    } else {
      return super.toString();
    }
  }
}

class BezierCurveTo extends PathCommand {
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double x3;
  final double y3;

  const BezierCurveTo(this.x1, this.y1, this.x2, this.y2, this.x3, this.y3)
      : super(PathCommandTypes.bezierCurveTo);

  @override
  BezierCurveTo shifted(Offset offset) {
    return new BezierCurveTo(x1 + offset.dx, y1 + offset.dy, x2 + offset.dx,
        y2 + offset.dy, x3 + offset.dx, y3 + offset.dy);
  }

  @override
  List serializeToCssPaint() {
    return [5, x1, y1, x2, y2, x3, y3];
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'BezierCurveTo($x1, $y1, $x2, $y2, $x3, $y3)';
    } else {
      return super.toString();
    }
  }
}

class RectCommand extends PathCommand {
  final double x;
  final double y;
  final double width;
  final double height;

  const RectCommand(this.x, this.y, this.width, this.height)
      : super(PathCommandTypes.rect);

  @override
  RectCommand shifted(Offset offset) {
    return new RectCommand(x + offset.dx, y + offset.dy, width, height);
  }

  @override
  List serializeToCssPaint() {
    return [6, x, y, width, height];
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'Rect($x, $y, $width, $height)';
    } else {
      return super.toString();
    }
  }
}

class RRectCommand extends PathCommand {
  final RRect rrect;

  const RRectCommand(this.rrect) : super(PathCommandTypes.rRect);

  @override
  RRectCommand shifted(Offset offset) {
    return new RRectCommand(rrect.shift(offset));
  }

  @override
  List serializeToCssPaint() {
    return [7, _serializeRRectToCssPaint(rrect)];
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return '$rrect';
    } else {
      return super.toString();
    }
  }
}

class CloseCommand extends PathCommand {
  const CloseCommand() : super(PathCommandTypes.close);

  @override
  CloseCommand shifted(Offset offset) {
    return this;
  }

  @override
  List serializeToCssPaint() {
    return [8];
  }

  @override
  String toString() {
    if (assertionsEnabled) {
      return 'Close()';
    } else {
      return super.toString();
    }
  }
}

class _PaintBounds {
  // Bounds of maximum area that is paintable by canvas ops.
  final Rect maxPaintBounds;

  bool _didPaintInsideClipArea = false;
  // Bounds of actually painted area. If _left is not set, reported paintBounds
  // should be empty since growLTRB calls were outside active clipping
  // region.
  double _left, _top, _right, _bottom;
  // Stack of transforms.
  List<Matrix4> _transforms;
  // Stack of clip bounds.
  List<Rect> _clipStack;
  bool _currentMatrixIsIdentity = true;
  Matrix4 _currentMatrix = Matrix4.identity();
  bool _clipRectInitialized = false;
  double _currentClipLeft = 0.0,
      _currentClipTop = 0.0,
      _currentClipRight = 0.0,
      _currentClipBottom = 0.0;

  _PaintBounds(this.maxPaintBounds);

  void translate(double dx, double dy) {
    if (dx != 0.0 || dy != 0.0) _currentMatrixIsIdentity = false;
    _currentMatrix.translate(dx, dy);
  }

  void scale(double sx, double sy) {
    if (sx != 1.0 || sy != 1.0) _currentMatrixIsIdentity = false;
    _currentMatrix.scale(sx, sy);
  }

  void rotateZ(double radians) {
    if (radians != 0.0) _currentMatrixIsIdentity = false;
    _currentMatrix.rotateZ(radians);
  }

  void transform(Float64List matrix4) {
    var m4 = new Matrix4.fromFloat64List(matrix4);
    _currentMatrix.multiply(m4);
    _currentMatrixIsIdentity = _currentMatrix.isIdentity();
  }

  void skew(double sx, double sy) {
    _currentMatrixIsIdentity = false;
    _currentMatrix.multiply(new Matrix4.skew(sx, sy));
  }

  void clipRect(Rect rect) {
    // If we have an active transform, calculate screen relative clipping
    // rectangle and union with current clipping rectangle.
    if (!_currentMatrixIsIdentity) {
      Vector3 leftTop =
          _currentMatrix.transform3(Vector3(rect.left, rect.top, 0.0));
      Vector3 rightTop =
          _currentMatrix.transform3(Vector3(rect.right, rect.top, 0.0));
      Vector3 leftBottom =
          _currentMatrix.transform3(Vector3(rect.left, rect.bottom, 0.0));
      Vector3 rightBottom =
          _currentMatrix.transform3(Vector3(rect.right, rect.bottom, 0.0));
      rect = Rect.fromLTRB(
          math.min(math.min(math.min(leftTop.x, rightTop.x), leftBottom.x),
              rightBottom.x),
          math.min(math.min(math.min(leftTop.y, rightTop.y), leftBottom.y),
              rightBottom.y),
          math.max(math.max(math.max(leftTop.x, rightTop.x), leftBottom.x),
              rightBottom.x),
          math.max(math.max(math.max(leftTop.y, rightTop.y), leftBottom.y),
              rightBottom.y));
    }
    if (!_clipRectInitialized) {
      _currentClipLeft = rect.left;
      _currentClipTop = rect.top;
      _currentClipRight = rect.right;
      _currentClipBottom = rect.bottom;
      _clipRectInitialized = true;
    } else {
      if (rect.left > _currentClipLeft) _currentClipLeft = rect.left;
      if (rect.top > _currentClipTop) _currentClipTop = rect.top;
      if (rect.right < _currentClipRight) {
        _currentClipRight = rect.right;
      }
      if (rect.bottom < _currentClipBottom) _currentClipBottom = rect.bottom;
    }
  }

  /// Grow painted area to include given rectangle.
  void grow(Rect r) {
    growLTRB(r.left, r.top, r.right, r.bottom);
  }

  /// Grow painted area to include given rectangle.
  void growLTRB(double left, double top, double right, double bottom) {
    assert(left <= right);
    assert(top <= bottom);
    if (left == right || top == bottom) return;

    var transformedPointLeft = left;
    var transformedPointTop = top;
    var transformedPointRight = right;
    var transformedPointBottom = bottom;
    if (!_currentMatrixIsIdentity) {
      Vector3 leftTop = _currentMatrix.transform3(Vector3(left, top, 0.0));
      transformedPointLeft = leftTop.x;
      transformedPointTop = leftTop.y;
      Vector3 rightBottom =
          _currentMatrix.transform3(Vector3(right, bottom, 0.0));
      transformedPointRight = rightBottom.x;
      transformedPointBottom = rightBottom.y;
    }

    if (_clipRectInitialized) {
      if (transformedPointLeft > _currentClipRight) return;
      if (transformedPointRight < _currentClipLeft) return;
      if (transformedPointTop > _currentClipBottom) return;
      if (transformedPointBottom < _currentClipTop) return;
      if (transformedPointLeft < _currentClipLeft) {
        transformedPointLeft = _currentClipLeft;
      }
      if (transformedPointRight > _currentClipRight) {
        transformedPointRight = _currentClipRight;
      }
      if (transformedPointTop < _currentClipTop) {
        transformedPointTop = _currentClipTop;
      }
      if (transformedPointBottom > _currentClipBottom) {
        transformedPointBottom = _currentClipBottom;
      }
    }

    if (_didPaintInsideClipArea) {
      _left = math.min(
          math.min(_left, transformedPointLeft), transformedPointRight);
      _right = math.max(
          math.max(_right, transformedPointLeft), transformedPointRight);
      _top =
          math.min(math.min(_top, transformedPointTop), transformedPointBottom);
      _bottom = math.max(
          math.max(_bottom, transformedPointTop), transformedPointBottom);
    } else {
      _left = math.min(transformedPointLeft, transformedPointRight);
      _right = math.max(transformedPointLeft, transformedPointRight);
      _top = math.min(transformedPointTop, transformedPointBottom);
      _bottom = math.max(transformedPointTop, transformedPointBottom);
    }
    _didPaintInsideClipArea = true;
  }

  void saveTransformsAndClip() {
    _clipStack ??= [];
    _transforms ??= [];
    _transforms.add(_currentMatrix?.clone());
    _clipStack.add(_clipRectInitialized
        ? new Rect.fromLTRB(_currentClipLeft, _currentClipTop,
            _currentClipRight, _currentClipBottom)
        : null);
  }

  void restoreTransformsAndClip() {
    _currentMatrix = _transforms.removeLast();
    Rect clipRect = _clipStack.removeLast();
    if (clipRect != null) {
      _currentClipLeft = clipRect.left;
      _currentClipTop = clipRect.top;
      _currentClipRight = clipRect.right;
      _currentClipBottom = clipRect.bottom;
      _clipRectInitialized = true;
    } else if (_clipRectInitialized) {
      _clipRectInitialized = false;
    }
  }

  Rect computeBounds() {
    if (!_didPaintInsideClipArea) return Rect.zero;

    // The framework may send us NaNs in the case when it attempts to invert an
    // infinitely size rect.
    final double maxLeft = maxPaintBounds.left.isNaN
        ? double.negativeInfinity
        : maxPaintBounds.left;
    final double maxRight =
        maxPaintBounds.right.isNaN ? double.infinity : maxPaintBounds.right;
    final double maxTop =
        maxPaintBounds.top.isNaN ? double.negativeInfinity : maxPaintBounds.top;
    final double maxBottom =
        maxPaintBounds.bottom.isNaN ? double.infinity : maxPaintBounds.bottom;

    final double left = math.min(_left, _right);
    final double right = math.max(_left, _right);
    final double top = math.min(_top, _bottom);
    final double bottom = math.max(_top, _bottom);

    if (right < maxLeft || bottom < maxTop) {
      // Computed and max bounds do not intersect.
      return Rect.zero;
    }

    return Rect.fromLTRB(
      math.max(left, maxLeft),
      math.max(top, maxTop),
      math.min(right, maxRight),
      math.min(bottom, maxBottom),
    );
  }
}
