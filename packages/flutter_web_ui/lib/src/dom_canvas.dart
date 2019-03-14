// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:html' as html;
import 'package:vector_math/vector_math_64.dart';

import 'canvas.dart';
import 'dom_renderer.dart';
import 'engine_canvas.dart';
import 'geometry.dart';
import 'painting.dart';
import 'text.dart';
import 'util.dart';

/// A canvas that renders to DOM elements and CSS properties.
class DomCanvas extends EngineCanvas with SaveStackTracking {
  final html.Element rootElement = new html.Element.tag('flt-dom-canvas');

  DomCanvas() {
    rootElement.style
      ..position = 'absolute'
      ..top = '0'
      ..right = '0'
      ..bottom = '0'
      ..left = '0';
  }

  /// Prepare to reuse this canvas by clearing it's current contents.
  void clear() {
    super.clear();
    // TODO(yjbanov): we should measure if reusing old elements is beneficial.
    domRenderer.clearDom(rootElement);
  }

  void clipRect(Rect rect) {
    throw UnimplementedError();
  }

  void clipRRect(RRect rrect) {
    throw UnimplementedError();
  }

  void clipPath(Path path) {
    throw UnimplementedError();
  }

  void drawColor(Color color, BlendMode blendMode) {
    // TODO(yjbanov): implement blendMode
    html.Element box = html.Element.tag('draw-color');
    box.style
      ..position = 'absolute'
      ..top = '0'
      ..right = '0'
      ..bottom = '0'
      ..left = '0'
      ..backgroundColor = color.toCssString();
    currentElement.append(box);
  }

  void drawLine(Offset p1, Offset p2, PaintData paint) {
    throw UnimplementedError();
  }

  void drawPaint(PaintData paint) {
    throw UnimplementedError();
  }

  void drawRect(Rect rect, PaintData paint) {
    assert(paint.shader == null);
    final rectangle = html.Element.tag('draw-rect');
    assert(() {
      rectangle.setAttribute('flt-rect', '$rect');
      rectangle.setAttribute('flt-paint', '$paint');
      return true;
    }());
    String effectiveTransform;
    bool isStroke = paint.style == PaintingStyle.stroke;
    if (currentTransform.isIdentity()) {
      if (isStroke) {
        effectiveTransform =
            'translate(${rect.left - (paint.strokeWidth / 2.0)}px, ${rect.top - (paint.strokeWidth / 2.0)}px)';
      } else {
        effectiveTransform = 'translate(${rect.left}px, ${rect.top}px)';
      }
    } else {
      // Clone to avoid mutating _transform.
      Matrix4 translated = currentTransform.clone();
      if (isStroke) {
        translated.translate(rect.left - (paint.strokeWidth / 2.0),
            rect.top - (paint.strokeWidth / 2.0));
      } else {
        translated.translate(rect.left, rect.top);
      }
      effectiveTransform = matrix4ToCssTransform(translated);
    }
    var style = rectangle.style;
    style
      ..position = 'absolute'
      ..transformOrigin = '0 0 0'
      ..transform = effectiveTransform;

    final String cssColor = paint.color?.toCssString() ?? '#000000';

    if (isStroke) {
      style
        ..width = '${rect.width - paint.strokeWidth}px'
        ..height = '${rect.height - paint.strokeWidth}px'
        ..border = '${paint.strokeWidth}px solid ${cssColor}';
    } else {
      style
        ..width = '${rect.width}px'
        ..height = '${rect.height}px'
        ..backgroundColor = cssColor;
    }

    currentElement.append(rectangle);
  }

  void drawRRect(RRect rrect, PaintData paint) {
    throw UnimplementedError();
  }

  void drawDRRect(RRect outer, RRect inner, PaintData paint) {
    throw UnimplementedError();
  }

  void drawOval(Rect rect, PaintData paint) {
    throw UnimplementedError();
  }

  void drawCircle(Offset c, double radius, PaintData paint) {
    throw UnimplementedError();
  }

  void drawPath(Path path, PaintData paint) {
    throw UnimplementedError();
  }

  void drawShadow(
      Path path, Color color, double elevation, bool transparentOccluder) {
    throw UnimplementedError();
  }

  void drawImage(Image image, Offset p, PaintData paint) {
    throw UnimplementedError();
  }

  void drawImageRect(Image image, Rect src, Rect dst, PaintData paint) {
    throw UnimplementedError();
  }

  void drawParagraph(Paragraph paragraph, Offset offset) {
    assert(paragraph.webOnlyIsLaidOut);

    html.Element paragraphElement =
        paragraph.webOnlyGetParagraphElement().clone(true);

    String cssTransform =
        matrix4ToCssTransform(transformWithOffset(currentTransform, offset));

    paragraphElement.style
      ..position = 'absolute'
      ..transformOrigin = '0 0 0'
      ..transform = cssTransform
      ..whiteSpace = 'pre-wrap'
      ..width = '${paragraph.width}px'
      ..height = '${paragraph.height}px';
    currentElement.append(paragraphElement);
  }
}
