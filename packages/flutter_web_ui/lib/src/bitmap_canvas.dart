// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

part of engine;

/// A raw HTML canvas that is directly written to.
class BitmapCanvas extends EngineCanvas with SaveStackTracking {
  /// The rectangle positioned relative to the parent layer's coordinate
  /// system's origin, within which this canvas paints.
  ///
  /// Painting outside these bounds will result in cropping.
  ui.Rect bounds;

  final html.Element rootElement = new html.Element.tag('flt-canvas');
  html.CanvasElement _canvas;
  html.CanvasRenderingContext2D _ctx;

  /// The size of the paint [bounds].
  ui.Size get size => bounds.size;

  /// The last paragraph style is cached to optimize the case where the style
  /// hasn't changed.
  ParagraphGeometricStyle _cachedLastStyle;

  final _paragraphs = new Set<html.Element>();

  /// The number of pixels along the width of the bitmap that the canvas element
  /// renders into.
  ///
  /// These pixels are different from the logical CSS pixels. Here a pixel
  /// literally means 1 point with a RGBA color.
  int get widthInBitmapPixels => _widthInBitmapPixels;
  int _widthInBitmapPixels;

  /// The number of pixels along the width of the bitmap that the canvas element
  /// renders into.
  ///
  /// These pixels are different from the logical CSS pixels. Here a pixel
  /// literally means 1 point with a RGBA color.
  int get heightInBitmapPixels => _heightInBitmapPixels;
  int _heightInBitmapPixels;

  /// The number of pixels in the bitmap that the canvas element renders into.
  ///
  /// These pixels are different from the logical CSS pixels. Here a pixel
  /// literally means 1 point with a RGBA color.
  int get bitmapPixelCount => widthInBitmapPixels * heightInBitmapPixels;

  int _saveCount = 0;

  /// Keeps track of what device pixel ratio was used when this [BitmapCanvas]
  /// was created.
  final double _devicePixelRatio = html.window.devicePixelRatio;

  /// Allocates a canvas with enough memory to paint a picture within the given
  /// [bounds].
  ///
  /// This canvas can be reused by pictures with different paint bounds as long
  /// as the [Rect.size] of the bounds fully fit within the size used to
  /// initialize this canvas.
  BitmapCanvas(this.bounds) {
    rootElement.style.position = 'absolute';

    // Adds one extra pixel to the requested size. This is to compensate for
    // _initializeViewport() snapping canvas position to 1 pixel, causing
    // painting to overflow by at most 1 pixel.
    final double boundsWidth = size.width + 1;
    final double boundsHeight = size.height + 1;
    _widthInBitmapPixels = (boundsWidth * html.window.devicePixelRatio).ceil();
    _heightInBitmapPixels =
        (boundsHeight * html.window.devicePixelRatio).ceil();

    // Compute the final CSS canvas size given the actual pixel count we
    // allocated. This is done for the following reasons:
    //
    // * To satisfy the invariant: pixel size = css size * device pixel ratio.
    // * To make sure that when we scale the canvas by devicePixelRatio (see
    //   _initializeViewport below) the pixels line up.
    final double cssWidth = _widthInBitmapPixels / html.window.devicePixelRatio;
    final double cssHeight =
        _heightInBitmapPixels / html.window.devicePixelRatio;

    _canvas = new html.CanvasElement(
      width: _widthInBitmapPixels,
      height: _heightInBitmapPixels,
    );
    _canvas.style
      ..position = 'absolute'
      ..width = '${cssWidth}px'
      ..height = '${cssHeight}px';
    _ctx = _canvas.context2D;
    rootElement.append(_canvas);
    _initializeViewport();
  }

  /// Prepare to reuse this canvas by clearing it's current contents.
  @override
  void clear() {
    super.clear();
    _paragraphs.forEach((p) => p.remove());
    _paragraphs.clear();
    _cachedLastStyle = null;
    // Restore to the state where we have only applied the scaling.
    if (_ctx != null) {
      _ctx.restore();
      _ctx.clearRect(0, 0, _widthInBitmapPixels, _heightInBitmapPixels);
      _ctx.font = '';
      _initializeViewport();
    }
    if (_canvas != null) {
      _canvas.style.transformOrigin = '';
      _canvas.style.transform = '';
    }
  }

  /// Checks whether this [BitmapCanvas] can still be recycled and reused.
  ///
  /// See also:
  ///
  /// * [PersistedStandardPicture._applyBitmapPaint] which uses this method to
  ///   decide whether to reuse this canvas or not.
  /// * [PersistedStandardPicture._recycleCanvas] which also uses this method
  ///   for the same reason.
  bool isReusable() {
    return _devicePixelRatio == html.window.devicePixelRatio;
  }

  /// Configures the canvas such that its coordinate system follows the scene's
  /// coordinate system, and the pixel ratio is applied such that CSS pixels are
  /// translated to bitmap pixels.
  void _initializeViewport() {
    // Save the canvas state with top-level transforms so we can undo
    // any clips later when we reuse the canvas.
    _ctx.save();

    // We always start with identity transform because the surrounding transform
    // is applied on the DOM elements.
    _ctx.setTransform(1, 0, 0, 1, 0, 0);

    // This scale makes sure that 1 CSS pixel is translated to the correct
    // number of bitmap pixels.
    _ctx.scale(html.window.devicePixelRatio, html.window.devicePixelRatio);

    // Flutter emits paint operations positioned relative to the parent layer's
    // coordinate system. However, canvas' coordinate system's origin is always
    // in the top-left corner of the canvas. We therefore need to inject an
    // initial translation so the paint operations are positioned as expected.
    if (bounds.left != 0.0 || bounds.top != 0.0) {
      // The flooring of the value is to ensure that canvas' top-left corner
      // lands on the physical pixel.
      final int canvasPositionX = bounds.left.floor();
      final int canvasPositionY = bounds.top.floor();
      final double canvasPositionCorrectionX =
          bounds.left - canvasPositionX.toDouble();
      final double canvasPositionCorrectionY =
          bounds.top - canvasPositionY.toDouble();

      rootElement.style.transform =
          'translate(${canvasPositionX}px, ${canvasPositionY}px)';

      // This compensates for the translate on the `rootElement`.
      translate(
        -bounds.left + canvasPositionCorrectionX,
        -bounds.top + canvasPositionCorrectionY,
      );
    } else {
      rootElement.style.transform = null;
    }
  }

  /// The `<canvas>` element used by this bitmap canvas.
  html.CanvasElement get canvas => _canvas;

  /// The 2D context of the `<canvas>` element used by this bitmap canvas.
  html.CanvasRenderingContext2D get ctx => _ctx;

  /// Sets the global paint styles to correspond to [paint].
  void _applyPaint(ui.PaintData paint) {
    ctx.globalCompositeOperation =
        _stringForBlendMode(paint.blendMode) ?? 'source-over';
    ctx.lineWidth = paint.strokeWidth ?? 1.0;
    var cap = paint.strokeCap;
    if (cap != null) {
      ctx.lineCap = _stringForStrokeCap(cap);
    } else {
      ctx.lineCap = 'butt';
    }
    var join = paint.strokeJoin;
    if (join != null) {
      ctx.lineJoin = _stringForStrokeJoin(join);
    } else {
      ctx.lineJoin = 'miter';
    }
    if (paint.shader != null) {
      var paintStyle = paint.shader.createPaintStyle(ctx);
      ctx.fillStyle = paintStyle;
      ctx.strokeStyle = paintStyle;
    } else if (paint.color != null) {
      var colorString = paint.color.toCssString();
      ctx.fillStyle = colorString;
      ctx.strokeStyle = colorString;
    }
    if (paint.maskFilter != null) {
      ctx.filter = 'blur(${paint.maskFilter.webOnlySigma}px)';
    }
  }

  void _strokeOrFill(ui.PaintData paint, {bool resetPaint = true}) {
    switch (paint.style) {
      case ui.PaintingStyle.stroke:
        ctx.stroke();
        break;
      case ui.PaintingStyle.fill:
      default:
        ctx.fill();
        break;
    }
    if (resetPaint) {
      _resetPaint();
    }
  }

  /// Resets the paint styles that were set due to a previous paint command.
  ///
  /// For example, if a previous paint commands has a blur filter, we need to
  /// undo that filter here.
  ///
  /// This needs to be called after [_applyPaint].
  void _resetPaint() {
    ctx.filter = 'none';
    ctx.fillStyle = null;
    ctx.strokeStyle = null;
  }

  @override
  int save() {
    super.save();
    ctx.save();
    return _saveCount++;
  }

  void saveLayer(ui.Rect bounds, _) {
    save();
  }

  @override
  void restore() {
    super.restore();
    ctx.restore();
    _saveCount--;
    _cachedLastStyle = null;
  }

  // TODO(yjbanov): not sure what this is attempting to do, but it is probably
  //                wrong because some clips and transforms are expressed using
  //                HTML DOM elements.
  void restoreToCount(int count) {
    assert(_saveCount >= count);
    int restores = _saveCount - count;
    for (int i = 0; i < restores; i++) {
      ctx.restore();
    }
    _saveCount = count;
  }

  @override
  void translate(double dx, double dy) {
    super.translate(dx, dy);
    ctx.translate(dx, dy);
  }

  @override
  void scale(double sx, double sy) {
    super.scale(sx, sy);
    ctx.scale(sx, sy);
  }

  @override
  void rotate(double radians) {
    super.rotate(radians);
    ctx.rotate(radians);
  }

  @override
  void skew(double sx, double sy) {
    super.skew(sx, sy);
    ctx.transform(1, sy, sx, 1, 0, 0);
    //            |  |   |   |  |  |
    //            |  |   |   |  |  f - vertical translation
    //            |  |   |   |  e - horizontal translation
    //            |  |   |   d - vertical scaling
    //            |  |   c - horizontal skewing
    //            |  b - vertical skewing
    //            a - horizontal scaling
    //
    // Source: https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/transform
  }

  @override
  void transform(Float64List matrix4) {
    super.transform(matrix4);

    // Canvas2D transform API:
    //
    // ctx.transform(a, b, c, d, e, f);
    //
    // In 3x3 matrix form assuming vector representation of (x, y, 1):
    //
    // a c e
    // b d f
    // 0 0 1
    //
    // This translates to 4x4 matrix with vector representation of (x, y, z, 1)
    // as:
    //
    // a c 0 e
    // b d 0 f
    // 0 0 1 0
    // 0 0 0 1
    //
    // This matrix is sufficient to represent 2D rotates, translates, scales,
    // and skews.
    assert(() {
      if (matrix4[2] != 0.0 ||
          matrix4[3] != 0.0 ||
          matrix4[7] != 0.0 ||
          matrix4[8] != 0.0 ||
          matrix4[9] != 0.0 ||
          matrix4[10] != 1.0 ||
          matrix4[11] != 0.0 ||
          matrix4[14] != 0.0 ||
          matrix4[15] != 1.0) {
        print('WARNING: 3D transformation matrix was passed to BitmapCanvas.');
      }
      return true;
    }());
    _ctx.transform(
      matrix4[0],
      matrix4[1],
      matrix4[4],
      matrix4[5],
      matrix4[12],
      matrix4[13],
    );
  }

  @override
  void clipRect(ui.Rect rect) {
    ctx.beginPath();
    ctx.rect(rect.left, rect.top, rect.width, rect.height);
    ctx.clip();
  }

  @override
  void clipRRect(ui.RRect rrect) {
    var path = new ui.Path()..addRRect(rrect);
    _runPath(path);
    ctx.clip();
  }

  @override
  void clipPath(ui.Path path) {
    _runPath(path);
    ctx.clip();
  }

  @override
  void drawColor(ui.Color color, ui.BlendMode blendMode) {
    ctx.globalCompositeOperation = _stringForBlendMode(blendMode);

    // Fill a virtually infinite rect with the color.
    //
    // We can't use (0, 0, width, height) because the current transform can
    // cause it to not fill the entire clip.
    ctx.fillRect(-10000, -10000, 20000, 20000);
  }

  @override
  void drawLine(ui.Offset p1, ui.Offset p2, ui.PaintData paint) {
    _applyPaint(paint);
    ctx.beginPath();
    ctx.moveTo(p1.dx, p1.dy);
    ctx.lineTo(p2.dx, p2.dy);
    ctx.stroke();
    _resetPaint();
  }

  @override
  void drawPaint(ui.PaintData paint) {
    _applyPaint(paint);
    ctx.beginPath();

    // Fill a virtually infinite rect with the color.
    //
    // We can't use (0, 0, width, height) because the current transform can
    // cause it to not fill the entire clip.
    ctx.fillRect(-10000, -10000, 20000, 20000);
    _resetPaint();
  }

  @override
  void drawRect(ui.Rect rect, ui.PaintData paint) {
    _applyPaint(paint);
    ctx.beginPath();
    ctx.rect(rect.left, rect.top, rect.width, rect.height);
    _strokeOrFill(paint);
  }

  @override
  void drawRRect(ui.RRect rrect, ui.PaintData paint) {
    _applyPaint(paint);
    _drawRRectPath(rrect);
    _strokeOrFill(paint);
  }

  void _drawRRectPath(ui.RRect rrect, {bool startNewPath = true}) {
    // TODO(mdebbar): there's a bug in this code, it doesn't correctly handle
    //                the case when the radius is greater than the width of the
    //                rect. When we fix that in houdini_painter.js, we need to
    //                fix it here too.
    // To draw the rounded rectangle, perform the following 8 steps:
    //   1. Flip left,right top,bottom since web doesn't support flipped
    //      coordinates with negative radii.
    //   2. draw the line for the top
    //   3. draw the arc for the top-right corner
    //   4. draw the line for the right side
    //   5. draw the arc for the bottom-right corner
    //   6. draw the line for the bottom of the rectangle
    //   7. draw the arc for the bottom-left corner
    //   8. draw the line for the left side
    //   9. draw the arc for the top-left corner
    //
    // After drawing, the current point will be the left side of the top of the
    // rounded rectangle (after the corner).
    // TODO(het): Confirm that this is the end point in Flutter for RRect

    var left = rrect.left;
    var right = rrect.right;
    var top = rrect.top;
    var bottom = rrect.bottom;
    if (left > right) {
      left = right;
      right = rrect.left;
    }
    if (top > bottom) {
      top = bottom;
      bottom = rrect.top;
    }
    var trRadiusX = rrect.trRadiusX.abs();
    var tlRadiusX = rrect.tlRadiusX.abs();
    var trRadiusY = rrect.trRadiusY.abs();
    var tlRadiusY = rrect.tlRadiusY.abs();
    var blRadiusX = rrect.blRadiusX.abs();
    var brRadiusX = rrect.brRadiusX.abs();
    var blRadiusY = rrect.blRadiusY.abs();
    var brRadiusY = rrect.brRadiusY.abs();

    ctx.moveTo(left + trRadiusX, top);

    if (startNewPath) {
      ctx.beginPath();
    }

    // Top side and top-right corner
    ctx.lineTo(right - trRadiusX, top);
    ctx.ellipse(
      right - trRadiusX,
      top + trRadiusY,
      trRadiusX,
      trRadiusY,
      0,
      1.5 * math.pi,
      2.0 * math.pi,
      false,
    );

    // Right side and bottom-right corner
    ctx.lineTo(right, bottom - brRadiusY);
    ctx.ellipse(
      right - brRadiusX,
      bottom - brRadiusY,
      brRadiusX,
      brRadiusY,
      0,
      0,
      0.5 * math.pi,
      false,
    );

    // Bottom side and bottom-left corner
    ctx.lineTo(left + blRadiusX, bottom);
    ctx.ellipse(
      left + blRadiusX,
      bottom - blRadiusY,
      blRadiusX,
      blRadiusY,
      0,
      0.5 * math.pi,
      math.pi,
      false,
    );

    // Left side and top-left corner
    ctx.lineTo(left, top + tlRadiusY);
    ctx.ellipse(
      left + tlRadiusX,
      top + tlRadiusY,
      tlRadiusX,
      tlRadiusY,
      0,
      math.pi,
      1.5 * math.pi,
      false,
    );
  }

  void _drawRRectPathReverse(ui.RRect rrect, {bool startNewPath = true}) {
    var left = rrect.left;
    var right = rrect.right;
    var top = rrect.top;
    var bottom = rrect.bottom;
    var trRadiusX = rrect.trRadiusX.abs();
    var tlRadiusX = rrect.tlRadiusX.abs();
    var trRadiusY = rrect.trRadiusY.abs();
    var tlRadiusY = rrect.tlRadiusY.abs();
    var blRadiusX = rrect.blRadiusX.abs();
    var brRadiusX = rrect.brRadiusX.abs();
    var blRadiusY = rrect.blRadiusY.abs();
    var brRadiusY = rrect.brRadiusY.abs();

    if (left > right) {
      left = right;
      right = rrect.left;
    }
    if (top > bottom) {
      top = bottom;
      bottom = rrect.top;
    }
    // Draw the rounded rectangle, counterclockwise.
    ctx.moveTo(right - trRadiusX, top);

    if (startNewPath) {
      ctx.beginPath();
    }

    // Top side and top-left corner
    ctx.lineTo(left + tlRadiusX, top);
    ctx.ellipse(
      left + tlRadiusX,
      top + tlRadiusY,
      tlRadiusX,
      tlRadiusY,
      0,
      1.5 * math.pi,
      1 * math.pi,
      true,
    );

    // Left side and bottom-left corner
    ctx.lineTo(left, bottom - blRadiusY);
    ctx.ellipse(
      left + blRadiusX,
      bottom - blRadiusY,
      blRadiusX,
      blRadiusY,
      0,
      1 * math.pi,
      0.5 * math.pi,
      true,
    );

    // Bottom side and bottom-right corner
    ctx.lineTo(right - brRadiusX, bottom);
    ctx.ellipse(
      right - brRadiusX,
      bottom - brRadiusY,
      brRadiusX,
      brRadiusY,
      0,
      0.5 * math.pi,
      0 * math.pi,
      true,
    );

    // Right side and top-right corner
    ctx.lineTo(right, top + trRadiusY);
    ctx.ellipse(
      right - trRadiusX,
      top + trRadiusY,
      trRadiusX,
      trRadiusY,
      0,
      0 * math.pi,
      1.5 * math.pi,
      true,
    );
  }

  @override
  void drawDRRect(ui.RRect outer, ui.RRect inner, ui.PaintData paint) {
    _applyPaint(paint);
    _drawRRectPath(outer);
    _drawRRectPathReverse(inner, startNewPath: false);
    _strokeOrFill(paint);
  }

  @override
  void drawOval(ui.Rect rect, ui.PaintData paint) {
    _applyPaint(paint);
    ctx.beginPath();
    ctx.ellipse(rect.center.dx, rect.center.dy, rect.width / 2, rect.height / 2,
        0, 0, 2.0 * math.pi, false);
    _strokeOrFill(paint);
  }

  @override
  void drawCircle(ui.Offset c, double radius, ui.PaintData paint) {
    _applyPaint(paint);
    ctx.beginPath();
    ctx.ellipse(c.dx, c.dy, radius, radius, 0, 0, 2.0 * math.pi, false);
    _strokeOrFill(paint);
  }

  @override
  void drawPath(ui.Path path, ui.PaintData paint) {
    _applyPaint(paint);
    _runPath(path);
    _strokeOrFill(paint);
  }

  @override
  void drawShadow(ui.Path path, ui.Color color, double elevation,
      bool transparentOccluder) {
    final shadows = ElevationShadow.computeCanvasShadows(elevation, color);
    if (shadows.isNotEmpty) {
      for (final shadow in shadows) {
        // TODO(het): Shadows with transparent occluders are not supported
        // on webkit since filter is unsupported.
        if (transparentOccluder && browserEngine != BrowserEngine.webkit) {
          // We paint shadows using a path and a mask filter instead of the
          // built-in shadow* properties. This is because the color alpha of the
          // paint is added to the shadow. The effect we're looking for is to just
          // paint the shadow without the path itself, but if we use a non-zero
          // alpha for the paint the path is painted in addition to the shadow,
          // which is undesirable.
          final paint = ui.Paint()
            ..color = shadow.color
            ..style = ui.PaintingStyle.fill
            ..strokeWidth = 0.0
            ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, shadow.blur);
          _ctx.save();
          _ctx.translate(shadow.offsetX, shadow.offsetY);
          final paintData = paint.webOnlyPaintData;
          _applyPaint(paintData);
          _runPath(path);
          _strokeOrFill(paintData, resetPaint: false);
          _ctx.restore();
        } else {
          // TODO(het): We fill the path with this paint, then later we clip
          // by the same path and fill it with a fully opaque color (we know
          // the color is fully opaque because `transparentOccluder` is false.
          // However, due to anti-aliasing of the clip, a few pixels of the
          // path we are about to paint may still be visible after we fill with
          // the opaque occluder. For that reason, we fill with the shadow color,
          // and set the shadow color to fully opaque. This way, the visible
          // pixels are less opaque and less noticeable.
          final paint = ui.Paint()
            ..color = shadow.color
            ..style = ui.PaintingStyle.fill
            ..strokeWidth = 0.0;
          _ctx.save();
          final paintData = paint.webOnlyPaintData;
          _applyPaint(paintData);
          _ctx.shadowBlur = shadow.blur;
          _ctx.shadowColor = shadow.color.withAlpha(0xff).toCssString();
          _ctx.shadowOffsetX = shadow.offsetX;
          _ctx.shadowOffsetY = shadow.offsetY;
          _runPath(path);
          _strokeOrFill(paintData, resetPaint: false);
          _ctx.restore();
        }
      }
      _resetPaint();
    }
  }

  @override
  void drawImage(ui.Image image, ui.Offset p, ui.PaintData paint) {
    _applyPaint(paint);
    html.Element imgElement = (image as HtmlImage).imgElement.clone(true);
    imgElement.style
      ..position = 'absolute'
      ..transform = 'translate(${p.dx}px, ${p.dy}px)';
    rootElement.append(imgElement);
  }

  @override
  void drawImageRect(
      ui.Image image, ui.Rect src, ui.Rect dst, ui.PaintData paint) {
    // TODO(het): Check if the src rect is the entire image, and if so just
    // append the imgElement and set it's height and width.
    ctx.drawImageScaledFromSource(
      (image as HtmlImage).imgElement,
      src.left,
      src.top,
      src.width,
      src.height,
      dst.left,
      dst.top,
      dst.width,
      dst.height,
    );
  }

  @override
  void drawParagraph(ui.Paragraph paragraph, ui.Offset offset) {
    assert(paragraph.webOnlyIsLaidOut);

    if (paragraph.webOnlyDrawOnCanvas) {
      var style = paragraph.webOnlyGetParagraphGeometricStyle();
      if (style != _cachedLastStyle) {
        ctx.font = style.cssFontString;
        _cachedLastStyle = style;
      }
      _applyPaint(paragraph.webOnlyGetPaint().webOnlyPaintData);
      ctx.fillText(
          paragraph.webOnlyGetPlainText(),
          offset.dx + paragraph.webOnlyAlignOffset,
          offset.dy + paragraph.alphabeticBaseline);
      _resetPaint();
      return;
    }

    // This will cause a new canvas to be created for the next painting
    // operation. This ensures that shapes that appear on top of text are
    // rendered correctly.
    // TODO(yjbanov): as our sample apps show it is a very common case for text
    //                drawing operations to interleave non-text operations,
    //                which generates a lot of HTML canvases for a single
    //                Flutter Picture. This kills performance. We need a smarter
    //                strategy, such as deducing painting bounds from paint ops
    //                and/or sinking non-intersecting graphics down the canvas
    //                chain.
    // _canvas = null;

    html.Element paragraphElement =
        paragraph.webOnlyGetParagraphElement().clone(true);

    String cssTransform =
        matrix4ToCssTransform(transformWithOffset(currentTransform, offset));

    paragraphElement.style
      ..position = 'absolute'
      ..transform = cssTransform
      ..whiteSpace = 'pre-wrap'
      ..width = '${paragraph.width}px'
      ..height = '${paragraph.height}px';
    currentElement.append(paragraphElement);
    _paragraphs.add(paragraphElement);
  }

  /// Paints the [picture] into this canvas.
  void drawPicture(ui.Picture picture) {
    picture.recordingCanvas.apply(this);
  }

  /// 'Runs' the given [path] by applying all of its commands to the canvas.
  void _runPath(ui.Path path) {
    ctx.beginPath();
    for (var subpath in path.subpaths) {
      for (var command in subpath.commands) {
        switch (command.type) {
          case PathCommandTypes.bezierCurveTo:
            BezierCurveTo curve = command;
            ctx.bezierCurveTo(
                curve.x1, curve.y1, curve.x2, curve.y2, curve.x3, curve.y3);
            break;
          case PathCommandTypes.close:
            ctx.closePath();
            break;
          case PathCommandTypes.ellipse:
            Ellipse ellipse = command;
            ctx.ellipse(
                ellipse.x,
                ellipse.y,
                ellipse.radiusX,
                ellipse.radiusY,
                ellipse.rotation,
                ellipse.startAngle,
                ellipse.endAngle,
                ellipse.anticlockwise);
            break;
          case PathCommandTypes.lineTo:
            LineTo lineTo = command;
            ctx.lineTo(lineTo.x, lineTo.y);
            break;
          case PathCommandTypes.moveTo:
            MoveTo moveTo = command;
            ctx.moveTo(moveTo.x, moveTo.y);
            break;
          case PathCommandTypes.rRect:
            RRectCommand rrectCommand = command;
            _drawRRectPath(rrectCommand.rrect, startNewPath: false);
            break;
          case PathCommandTypes.rect:
            RectCommand rectCommand = command;
            ctx.rect(rectCommand.x, rectCommand.y, rectCommand.width,
                rectCommand.height);
            break;
          case PathCommandTypes.quadraticCurveTo:
            QuadraticCurveTo quadraticCurveTo = command;
            ctx.quadraticCurveTo(quadraticCurveTo.x1, quadraticCurveTo.y1,
                quadraticCurveTo.x2, quadraticCurveTo.y2);
            break;
          default:
            throw new UnimplementedError('Unknown path command $command');
        }
      }
    }
  }
}

String _stringForBlendMode(ui.BlendMode blendMode) {
  if (blendMode == null) return null;
  switch (blendMode) {
    case ui.BlendMode.srcOver:
      return 'source-over';
    case ui.BlendMode.srcIn:
      return 'source-in';
    case ui.BlendMode.srcOut:
      return 'source-out';
    case ui.BlendMode.srcATop:
      return 'source-atop';
    case ui.BlendMode.dstOver:
      return 'destination-over';
    case ui.BlendMode.dstIn:
      return 'destination-in';
    case ui.BlendMode.dstOut:
      return 'destination-out';
    case ui.BlendMode.dstATop:
      return 'destination-atop';
    case ui.BlendMode.plus:
      return 'lighten';
    case ui.BlendMode.src:
      return 'copy';
    case ui.BlendMode.xor:
      return 'xor';
    case ui.BlendMode.multiply:
    // Falling back to multiply, ignoring alpha channel.
    // TODO(flutter_web): only used for debug, find better fallback for web.
    case ui.BlendMode.modulate:
      return 'multiply';
    case ui.BlendMode.screen:
      return 'screen';
    case ui.BlendMode.overlay:
      return 'overlay';
    case ui.BlendMode.darken:
      return 'darken';
    case ui.BlendMode.lighten:
      return 'lighten';
    case ui.BlendMode.colorDodge:
      return 'color-dodge';
    case ui.BlendMode.colorBurn:
      return 'color-burn';
    case ui.BlendMode.hardLight:
      return 'hard-light';
    case ui.BlendMode.softLight:
      return 'soft-light';
    case ui.BlendMode.difference:
      return 'difference';
    case ui.BlendMode.exclusion:
      return 'exclusion';
    case ui.BlendMode.hue:
      return 'hue';
    case ui.BlendMode.saturation:
      return 'saturation';
    case ui.BlendMode.color:
      return 'color';
    case ui.BlendMode.luminosity:
      return 'luminosity';
    default:
      throw new UnimplementedError(
          'Flutter Web does not support the blend mode: $blendMode');
  }
}

String _stringForStrokeCap(ui.StrokeCap strokeCap) {
  if (strokeCap == null) return null;
  switch (strokeCap) {
    case ui.StrokeCap.butt:
      return 'butt';
    case ui.StrokeCap.round:
      return 'round';
    case ui.StrokeCap.square:
    default:
      return 'square';
  }
}

String _stringForStrokeJoin(ui.StrokeJoin strokeJoin) {
  assert(strokeJoin != null);
  switch (strokeJoin) {
    case ui.StrokeJoin.round:
      return 'round';
    case ui.StrokeJoin.bevel:
      return 'bevel';
    case ui.StrokeJoin.miter:
    default:
      return 'miter';
  }
}
