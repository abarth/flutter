// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'box.dart';
import 'object.dart';

class ViewportConstraints extends Constraints {
  const ViewportConstraints({
    this.mainAxis,
    this.crossAxisExtent,
    this.startOffset,
    this.endOffset
  });

  final Axis mainAxis;
  final double crossAxisExtent;
  final double startOffset;
  final double endOffset;

  double get availableOffset => endOffset - startOffset;

  double constrainOffset(double offset) => math.min(availableOffset, offset);

  ViewportConstraints copyWith({
    Axis mainAxis,
    double crossAxisExtent,
    double startOffset,
    double endOffset
  }) {
    return new ViewportConstraints(
      mainAxis: mainAxis ?? this.mainAxis,
      crossAxisExtent: crossAxisExtent ?? this.crossAxisExtent,
      startOffset: startOffset ?? this.startOffset,
      endOffset: endOffset ?? this.endOffset
    );
  }

  @override
  bool get isTight => false;

  @override
  bool get isNormalized => crossAxisExtent >= 0 && startOffset <= endOffset;

  ViewportConstraints normalize() {
    if (isNormalized)
      return this;
    return copyWith(
      crossAxisExtent: crossAxisExtent >= 0.0 ? crossAxisExtent : 0.0,
      startOffset: endOffset
    );
  }

  @override
  bool debugAssertIsValid({
    bool isAppliedConstraint: false,
    InformationCollector informationCollector
  }) => true;
}

enum ViewportPaintPhase {
  top,
  header,
  content,
}

class ViewportedItemParentData extends ParentData {
}

abstract class RenderViewportedItem extends RenderObject {
  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! ViewportedItemParentData)
      child.parentData = new ViewportedItemParentData();
  }

  double get offsetConsumed => _offsetConsumed;
  double _offsetConsumed;
  @protected
  set offsetConsumed (double value) {
    _offsetConsumed = value;
  }

  @override
  ViewportConstraints get constraints => super.constraints;

  Size get size {
    assert(constraints != null);
    assert(constraints.mainAxis != null);
    switch (constraints.mainAxis) {
      case Axis.horizontal:
        return new Size(offsetConsumed, constraints.crossAxisExtent);
      case Axis.vertical:
        return new Size(constraints.crossAxisExtent, offsetConsumed);
    }
    return null;
  }

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
    assert(offsetConsumed <= constraints.availableOffset);
  }

  @protected
  bool hitTestChildren(HitTestResult result, { double mainAxisOffset, double crossAxisOffset, ViewportPaintPhase phase }) => false;
}

class RenderViewportedPadding extends RenderViewportedItem with RenderObjectWithChildMixin<RenderViewportedItem> {
  RenderViewportedPadding({
    EdgeInsets padding,
    RenderViewportedItem child
  }) : _padding = padding {
    this.child = child;
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
    switch (constraints.mainAxis) {
      case Axis.horizontal:
        double offsetConsumedByChild = 0.0;
        if (child != null) {
          ViewportConstraints innerConstraints = constraints.copyWith(
            crossAxisExtent: constraints.crossAxisExtent - padding.vertical,
            startOffset: constraints.startOffset + padding.top,
            endOffset: constraints.endOffset - padding.bottom
          );
          child.layout(innerConstraints.normalize(), parentUsesSize: true);
          offsetConsumedByChild = child.offsetConsumed;
        }
        offsetConsumed = constraints.constrainOffset(offsetConsumedByChild + padding.horizontal);
        break;
      case Axis.vertical:
        double offsetConsumedByChild = 0.0;
        if (child != null) {
          ViewportConstraints innerConstraints = constraints.copyWith(
            crossAxisExtent: constraints.crossAxisExtent - padding.horizontal,
            startOffset: constraints.startOffset + padding.left,
            endOffset: constraints.endOffset - padding.right
          );
          child.layout(innerConstraints.normalize(), parentUsesSize: true);
          offsetConsumedByChild = child.offsetConsumed;
        }
        offsetConsumed = constraints.constrainOffset(offsetConsumedByChild + padding.vertical);
        break;
    }
  }

  // TODO(abarth): Need to offset painting and hit testing in the cross axis by
  // the amount we manipulated crossAxisExtent in performLayout.
}

abstract class ContainerViewportedItemParentDataMixin<ChildType extends RenderObject> extends ViewportedItemParentData with ContainerParentDataMixin<ChildType> { }

class RenderViewportedBox extends RenderViewportedItem with RenderObjectWithChildMixin<RenderBox> {
  RenderViewportedBox({ this.paintPhase, RenderBox child }) {
    this.child = child;
  }

  ViewportPaintPhase paintPhase;

  @override
  void performLayout() {
    if (child != null) {
      switch (constraints.mainAxis) {
        case Axis.horizontal:
          final BoxConstraints innerConstraints = new BoxConstraints.tightFor(height: constraints.crossAxisExtent);
          child.layout(innerConstraints, parentUsesSize: true);
          offsetConsumed = constraints.constrainOffset(child.size.width);
          break;
        case Axis.vertical:
          final BoxConstraints innerConstraints = new BoxConstraints.tightFor(width: constraints.crossAxisExtent);
          child.layout(innerConstraints, parentUsesSize: true);
          offsetConsumed = constraints.constrainOffset(child.size.height);
          break;
      }
    } else {
      offsetConsumed = 0.0;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null)
      context.paintChild(child, offset);
  }

  @override
  bool hitTestChildren(HitTestResult result, { double mainAxisOffset, double crossAxisOffset, ViewportPaintPhase phase }) {
    if (phase != paintPhase)
      return false;
    Point position;
    double relativeMainAxisOffset = mainAxisOffset - constraints.startOffset;
    switch (constraints.mainAxis) {
      case Axis.horizontal:
        position = new Point(relativeMainAxisOffset, crossAxisOffset);
        break;
      case Axis.vertical:
        position = new Point(crossAxisOffset, relativeMainAxisOffset);
        break;
    }
    return child.hitTest(result, position: position);
  }
}

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
    RenderViewportedItem child = firstChild;
    double currentOffset = constraints.startOffset;
    while (child != null) {
      child.layout(constraints.copyWith(startOffset: currentOffset).normalize(), parentUsesSize: true);
      final ViewportedListParentData childParentData = child.parentData;
      currentOffset += child.offsetConsumed;
      assert(child.parentData == childParentData);
      child = childParentData.nextSibling;
    }
    offsetConsumed = math.min(currentOffset, constraints.endOffset);
  }
}

class RenderViewport2 extends RenderBox with RenderObjectWithChildMixin<RenderViewportedItem> {
  RenderViewport2({
    Offset paintOffset,
    Axis mainAxis,
    RenderViewportedItem child
  }) {
    this.child = child;
  }

  double get startOffset => _startOffset;
  double _startOffset;
  set startOffset(double value) {
    assert(value != null);
    if (value == _startOffset)
      return;
    _startOffset = value;
    markNeedsPaint();
  }

  Axis get mainAxis => _mainAxis;
  Axis _mainAxis;
  set mainAxis(Axis value) {
    assert(value != null);
    if (value == _mainAxis)
      return;
    _mainAxis = value;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    return 0.0;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    return 0.0;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    return 0.0;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    return 0.0;
  }

  @override
  void performLayout() {
    if (child != null) {
      ViewportConstraints innerConstraints = new ViewportConstraints(
        mainAxis: mainAxis,
        crossAxisExtent: constraints.maxWidth,
        startOffset: startOffset,
        endOffset: startOffset + constraints.maxHeight
      );
      child.layout(constraints, parentUsesSize: true);
      size = child.size;
    } else {
      performResize();
    }
  }

  @override
  bool hitTestChildren(HitTestResult result, { Point position }) {
    return false;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
  }
}
