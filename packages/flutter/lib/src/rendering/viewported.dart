// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' as ui show window;

import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart';

import 'box.dart';
import 'object.dart';
import 'viewport.dart';

class ViewportConstraints extends Constraints {
  const ViewportConstraints({
    this.mainAxis,
    this.anchor,
    this.crossAxisExtent,
    this.interestStart,
    this.interestEnd
  });

  final Axis mainAxis;
  final ViewportAnchor anchor;
  final double crossAxisExtent;
  final double interestStart;
  final double interestEnd;

  double get interestExtent => interestEnd - interestEnd;

  ViewportConstraints shiftInterest(double offset) {
    return copyWith(
      interestStart: interestStart + offset,
      interestEnd: interestEnd + offset
    );
  }

  ViewportConstraints deflate(EdgeInsets edges) {
    assert(edges != null);
    assert(debugAssertIsValid());
    switch (mainAxis) {
      case Axis.horizontal:
        switch (anchor) {
          case ViewportAnchor.start:
            return copyWith(
              crossAxisExtent: crossAxisExtent - edges.vertical,
              interestStart: interestStart - edges.left,
              interestEnd: interestEnd - edges.left
            );
          case ViewportAnchor.end:
            return copyWith(
              crossAxisExtent: crossAxisExtent - edges.vertical,
              interestStart: interestStart - edges.right,
              interestEnd: interestEnd - edges.right
            );
        }
        break;
      case Axis.vertical:
        switch (anchor) {
          case ViewportAnchor.start:
            return copyWith(
              crossAxisExtent: crossAxisExtent - edges.horizontal,
              interestStart: interestStart - edges.top,
              interestEnd: interestEnd - edges.top
            );
          case ViewportAnchor.end:
            return copyWith(
              crossAxisExtent: crossAxisExtent - edges.horizontal,
              interestStart: interestStart - edges.bottom,
              interestEnd: interestEnd - edges.bottom
            );
        }
        break;
    }
    return null;
  }

  ViewportConstraints copyWith({
    Axis mainAxis,
    ViewportAnchor anchor,
    double crossAxisExtent,
    double interestStart,
    double interestEnd
  }) {
    return new ViewportConstraints(
      mainAxis: mainAxis ?? this.mainAxis,
      anchor: anchor ?? this.anchor,
      crossAxisExtent: crossAxisExtent ?? this.crossAxisExtent,
      interestStart: interestStart ?? this.interestStart,
      interestEnd: interestEnd ?? this.interestEnd
    );
  }

  @override
  bool get isTight => false;

  @override
  bool get isNormalized => crossAxisExtent >= 0.0 && interestStart <= interestEnd;

  ViewportConstraints normalize() {
    if (isNormalized)
      return this;
    return copyWith(
      crossAxisExtent: crossAxisExtent >= 0.0 ? crossAxisExtent : 0.0,
      interestStart: interestStart > interestEnd ? interestEnd : interestStart
    );
  }

  @override
  bool debugAssertIsValid({
    bool isAppliedConstraint: false,
    InformationCollector informationCollector
  }) => true;
}

class ViewportedItemParentData extends ParentData {
  Offset offset = Offset.zero;
}

abstract class RenderViewportedItem extends RenderObject {
  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! ViewportedItemParentData)
      child.parentData = new ViewportedItemParentData();
  }

  double get mainAxisExtent => _mainAxisExtent;
  double _mainAxisExtent;
  @protected
  set mainAxisExtent (double value) {
    _mainAxisExtent = value;
  }

  @override
  ViewportConstraints get constraints => super.constraints;

  Size getSizeForExtent(double mainAxisExtent) {
    assert(constraints.mainAxis != null);
    switch (constraints.mainAxis) {
      case Axis.horizontal:
        return new Size(mainAxisExtent, constraints.crossAxisExtent);
      case Axis.vertical:
        return new Size(constraints.crossAxisExtent, mainAxisExtent);
    }
    return null;
  }

  Offset getOffsetForExtent(double mainAxisExtent) {
    assert(constraints.mainAxis != null);
    assert(constraints.mainAxis != null);
    switch (constraints.mainAxis) {
      case Axis.horizontal:
        return new Offset(mainAxisExtent, 0.0);
      case Axis.vertical:
        return new Offset(0.0, mainAxisExtent);
    }
    return null;
  }

  Size get size => getSizeForExtent(mainAxisExtent);

  @override
  Rect get paintBounds => Point.origin & size;

  @override
  Rect get semanticBounds => Point.origin & size;

  @override
  void performResize() {
    assert(false);
  }

  @override
  void debugAssertDoesMeetConstraints() {
    assert(constraints != null);
  }

  bool hitTest(HitTestResult result, { @required double mainAxisOffset, @required double crossAxisOffset }) {
    if (mainAxisOffset >= 0.0 && mainAxisOffset < mainAxisExtent &&
        crossAxisOffset >= 0.0 && crossAxisOffset < constraints.crossAxisExtent) {
      if (hitTestChildren(result, mainAxisOffset: mainAxisOffset, crossAxisOffset: crossAxisOffset)
          || hitTestSelf(mainAxisOffset, crossAxisOffset)) {
        result.add(new HitTestEntry(this));
        return true;
      }
    }
    return false;
  }

  @protected
  bool hitTestSelf(double mainAxisOffset, double crossAxisOffset) => false;

  @protected
  bool hitTestChildren(HitTestResult result, { double mainAxisOffset, double crossAxisOffset }) => false;
}

abstract class RenderShiftedViewportedItem extends RenderViewportedItem with RenderObjectWithChildMixin<RenderViewportedItem> {
  RenderShiftedViewportedItem(RenderViewportedItem child) {
    this.child = child;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null) {
      final ViewportedItemParentData childParentData = child.parentData;
      context.paintChild(child, childParentData.offset + offset);
    }
  }

  @override
  bool hitTestChildren(HitTestResult result, { double mainAxisOffset, double crossAxisOffset }) {
    if (child != null) {
      final ViewportedItemParentData childParentData = child.parentData;
      switch (constraints.mainAxis) {
        case Axis.horizontal:
          mainAxisOffset -= childParentData.offset.dx;
          crossAxisOffset -= childParentData.offset.dy;
          break;
        case Axis.vertical:
          mainAxisOffset -= childParentData.offset.dy;
          crossAxisOffset -= childParentData.offset.dx;
          break;
      }
      return child.hitTest(result, mainAxisOffset: mainAxisOffset, crossAxisOffset: crossAxisOffset);
    }
    return false;
  }
}

class RenderViewportedPadding extends RenderShiftedViewportedItem {
  RenderViewportedPadding({
    EdgeInsets padding,
    RenderViewportedItem child
  }) : _padding = padding, super(child) {
    assert(padding != null);
    assert(padding.isNonNegative);
  }

  /// The amount to pad the child in each dimension.
  EdgeInsets get padding => _padding;
  EdgeInsets _padding;
  set padding (EdgeInsets value) {
    assert(value != null);
    assert(value.isNonNegative);
    if (_padding == value)
      return;
    _padding = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    double childMainAxisExtent = 0.0;
    if (child != null) {
      child.layout(constraints.deflate(padding), parentUsesSize: true);
      final ViewportedItemParentData childParentData = child.parentData;
      childParentData.offset = new Offset(padding.left, padding.top);
      childMainAxisExtent = child.mainAxisExtent;
    }
    mainAxisExtent = childMainAxisExtent + padding.along(constraints.mainAxis);
  }
}

class RenderViewportedBox extends RenderViewportedItem with RenderObjectWithChildMixin<RenderBox> {
  RenderViewportedBox({ RenderBox child }) {
    this.child = child;
  }

  @override
  void performLayout() {
    if (child != null) {
      switch (constraints.mainAxis) {
        case Axis.horizontal:
          final BoxConstraints innerConstraints = new BoxConstraints.tightFor(height: constraints.crossAxisExtent);
          child.layout(innerConstraints, parentUsesSize: true);
          final BoxParentData childParentData = child.parentData;
          childParentData.offset = Offset.zero;
          mainAxisExtent = child.size.width;
          break;
        case Axis.vertical:
          final BoxConstraints innerConstraints = new BoxConstraints.tightFor(width: constraints.crossAxisExtent);
          child.layout(innerConstraints, parentUsesSize: true);
          final BoxParentData childParentData = child.parentData;
          childParentData.offset = Offset.zero;
          mainAxisExtent = child.size.height;
          break;
      }
    } else {
      mainAxisExtent = 0.0;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null)
      context.paintChild(child, offset);
  }

  @override
  bool hitTestChildren(HitTestResult result, { double mainAxisOffset, double crossAxisOffset }) {
    assert(constraints.mainAxis != null);
    switch (constraints.mainAxis) {
      case Axis.horizontal:
        return child.hitTest(result, position: new Point(mainAxisOffset, crossAxisOffset));
      case Axis.vertical:
        return child.hitTest(result, position: new Point(crossAxisOffset, mainAxisOffset));
    }
    return false;
  }
}

abstract class ContainerViewportedItemParentDataMixin<ChildType extends RenderObject> extends ViewportedItemParentData with ContainerParentDataMixin<ChildType> { }

class ViewportedListParentData extends ContainerViewportedItemParentDataMixin<RenderViewportedItem> { }

class RenderViewportedList extends RenderViewportedItem with ContainerRenderObjectMixin<RenderViewportedItem, ViewportedListParentData> {
  RenderViewportedList({ List<RenderViewportedItem> children }) {
    addAll(children);
  }

  @override
  void setupParentData(RenderViewportedItem child) {
    if (child.parentData is! ViewportedListParentData)
      child.parentData = new ViewportedListParentData();
  }

  @override
  void performLayout() {
    double currentOffset = 0.0;
    RenderViewportedItem child = firstChild;
    while (child != null) {
      child.layout(constraints.shiftInterest(-currentOffset), parentUsesSize: true);
      final ViewportedListParentData childParentData = child.parentData;
      childParentData.offset = getOffsetForExtent(currentOffset);
      currentOffset += child.mainAxisExtent;
      child = childParentData.nextSibling;
    }
    mainAxisExtent = currentOffset;
  }
}

class RenderViewport2 extends RenderViewportBase with RenderObjectWithChildMixin<RenderViewportedItem> {
  RenderViewport2({
    RenderViewportedItem child,
    Offset paintOffset: Offset.zero,
    Axis mainAxis: Axis.vertical,
    ViewportAnchor anchor: ViewportAnchor.start,
    this.onPaintOffsetUpdateNeeded
  }) : super(paintOffset, mainAxis, anchor) {
    this.child = child;
  }

  ViewportDimensionsChangeCallback onPaintOffsetUpdateNeeded;

  @protected
  bool debugThrowIfNotCheckingIntrinsics() {
    assert(() {
      if (!RenderObject.debugCheckingIntrinsics) {
        throw new FlutterError(
          'RenderViewport2 does not support returning intrinsic dimensions.\n'
          'Calculating the intrinsic dimensions would require walking the entire '
          'child list, which cannot reliably and efficiently be done for render '
          'objects that potentially generate their child list during layout.'
        );
      }
      return true;
    });
    return true;
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    assert(debugThrowIfNotCheckingIntrinsics());
    return 0.0;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    assert(debugThrowIfNotCheckingIntrinsics());
    return 0.0;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    assert(debugThrowIfNotCheckingIntrinsics());
    return 0.0;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    assert(debugThrowIfNotCheckingIntrinsics());
    return 0.0;
  }

  ViewportConstraints _getInnerConstraints(BoxConstraints constraints) {
    assert(mainAxis != null);
    switch (mainAxis) {
      case Axis.horizontal:
        return new ViewportConstraints(
          mainAxis: mainAxis,
          crossAxisExtent: constraints.maxHeight,
          interestStart: paintOffset.dx,
          interestEnd: paintOffset.dx + constraints.maxWidth
        );
      case Axis.vertical:
        return new ViewportConstraints(
          mainAxis: mainAxis,
          crossAxisExtent: constraints.maxWidth,
          interestStart: paintOffset.dy,
          interestEnd: paintOffset.dy + constraints.maxHeight
        );
    }
    return null;
  }

  @override
  void performLayout() {
    final ViewportDimensions oldDimensions = dimensions;
    if (child != null) {
      child.layout(_getInnerConstraints(constraints), parentUsesSize: true);
      size = constraints.constrain(child.size);
      final ViewportedItemParentData childParentData = child.parentData;
      childParentData.offset = Offset.zero;
      dimensions = new ViewportDimensions(containerSize: size, contentSize: child.size);
    } else {
      performResize();
      dimensions = new ViewportDimensions(containerSize: size);
    }
    if (onPaintOffsetUpdateNeeded != null && dimensions != oldDimensions)
      paintOffset = onPaintOffsetUpdateNeeded(dimensions);
    assert(paintOffset != null);
  }

  bool _shouldClipAtPaintOffset(Offset paintOffset) {
    assert(child != null);
    return paintOffset < Offset.zero || !(Offset.zero & size).contains((paintOffset & child.size).bottomRight);
  }

  // TODO(abarth): Share with RenderViewportBase.
  Offset get _effectivePaintOffset {
    final double devicePixelRatio = ui.window.devicePixelRatio;
    int dxInDevicePixels = (paintOffset.dx * devicePixelRatio).round();
    int dyInDevicePixels = (paintOffset.dy * devicePixelRatio).round();
    return dimensions.getAbsolutePaintOffset(
      paintOffset: new Offset(dxInDevicePixels / devicePixelRatio, dyInDevicePixels / devicePixelRatio),
      anchor: anchor
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null) {
      final Offset effectivePaintOffset = _effectivePaintOffset;

      void paintContents(PaintingContext context, Offset offset) {
        context.paintChild(child, offset + effectivePaintOffset);
      }

      if (_shouldClipAtPaintOffset(effectivePaintOffset)) {
        context.pushClipRect(needsCompositing, offset, Point.origin & size, paintContents);
      } else {
        paintContents(context, offset);
      }
    }
  }

  @override
  Rect describeApproximatePaintClip(RenderObject child) {
    if (child != null && _shouldClipAtPaintOffset(_effectivePaintOffset))
      return Point.origin & size;
    return null;
  }

  // Workaround for https://github.com/dart-lang/sdk/issues/25232
  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    super.applyPaintTransform(child, transform);
  }

  @override
  bool hitTestChildren(HitTestResult result, { Point position }) {
    if (child != null) {
      Point transformed = position + -_effectivePaintOffset;
      switch (mainAxis) {
        case Axis.horizontal:
          return child.hitTestChildren(result, mainAxisOffset: transformed.x, crossAxisOffset: transformed.y);
        case Axis.vertical:
          return child.hitTestChildren(result, mainAxisOffset: transformed.y, crossAxisOffset: transformed.x);
      }
    }
    return false;
  }
}
