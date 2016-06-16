// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' show Point, Offset, lerpDouble;
import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:meta/meta.dart';

Offset normalize(Offset offset) {
  return offset / offset.distance;
}

class MaterialArc {
  MaterialArc(this.a, this.b) {
    Offset delta = b - a;
    double distanceFromAtoB = delta.distance;
    Point c = new Point(b.x, a.y);
    double deltaX = delta.dx.abs();
    double deltaY = delta.dy.abs();
    double alpha = deltaX > deltaY ?
        math.acos((c - a).distance / distanceFromAtoB) :
        math.acos((c - b).distance / distanceFromAtoB);
    double beta = math.PI / 2.0 - alpha;
    _radius = distanceFromAtoB / math.cos(beta) / 2.0;

    Point d = new Point((a.x + b.x) / 2.0, (a.y + b.y) / 2.0);
    double distanceFromAToD = (d - a).distance;
    double distanceFromAToE = distanceFromAToD / math.cos(alpha);
    double distanceFromDToF = math.tan(beta) * distanceFromAToD;

    Point e;
    if (a.y == b.y)
      e = d;
    else if (deltaX > deltaY)
      e = a + normalize(c - a) * distanceFromAToE;
    else
      e = a + normalize(c - b) * distanceFromAToE;

    Point f = d + normalize(d - e) * distanceFromDToF;
    Offset startOffset = a - f;
    Offset endOffset = b - f;

    _center = f;
    _startAngle = math.atan(startOffset.dy/ startOffset.dx);
    _endAngle = math.atan(endOffset.dy / endOffset.dx);
  }

  final Point a;
  final Point b;

  Point _center;
  double _radius;
  double _startAngle;
  double _endAngle;

  Point transform(double t) {
    double angle = lerpDouble(_startAngle,_endAngle, t);
    double x = math.cos(angle) * _radius + _center.x;
    double y = math.sin(angle) * _radius + _center.y;
    return new Point(x, y);
  }
}

class MaterialArcAnimation extends Animation<Offset> with AnimationWithParentMixin<double> {
  MaterialArcAnimation({
    @required this.parent,
    @required this.arc
  }) {
    assert(parent != null);
    assert(arc != null);
  }

  @override
  final Animation<double> parent;

  MaterialArc arc;

  @override
  Offset get value {
    double t = parent.value;
    if (t == 0.0)
      return arc.a;
    else if (t == 1.0)
      return arc.b;
    return arc.transform(t);
  }
}
