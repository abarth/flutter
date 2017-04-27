// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'basic.dart';
import 'framework.dart';
import 'primary_scroll_controller.dart';
import 'scroll_activity.dart';
import 'scroll_context.dart';
import 'scroll_controller.dart';
import 'scroll_metrics.dart';
import 'scroll_physics.dart';
import 'scroll_position.dart';
import 'scroll_view.dart';
import 'sliver.dart';
import 'ticker_provider.dart';

typedef ScrollActivity _NestedScrollActivityGetter(_NestedScrollPosition position);

typedef List<Widget> NestedScrollViewOuterSliversBuilder(BuildContext context, bool innerBoxIsScrolled);

class NestedScrollView extends StatefulWidget {
  NestedScrollView({
    Key key,
    this.scrollDirection: Axis.vertical,
    this.reverse: false,
    this.physics,
    @required this.headerSliverBuilder,
    @required this.body,
  }) : super(key: key) {
    assert(scrollDirection != null);
    assert(reverse != null);
    assert(headerSliverBuilder != null);
    assert(body != null);
  }

  // TODO(ianh): we should expose a controller so you can call animateTo, etc.

  final Axis scrollDirection;

  final bool reverse;

  final ScrollPhysics physics;

  final NestedScrollViewOuterSliversBuilder headerSliverBuilder;

  final Widget body;

  double get initialScrollOffset => 0.0;

  @protected
  List<Widget> buildSlivers(BuildContext context, ScrollController innerController, bool bodyIsScrolled) {
    final List<Widget> slivers = <Widget>[];
    slivers.addAll(headerSliverBuilder(context, bodyIsScrolled));
    slivers.add(new SliverFillRemaining(
      child: new PrimaryScrollController(
        controller: innerController,
        child: body,
      ),
    ));
    return slivers;
  }

  @override
  _NestedScrollViewState createState() => new _NestedScrollViewState();
}

class _NestedScrollViewState extends State<NestedScrollView> implements ScrollActivityDelegate {
  @override
  void initState() {
    super.initState();
    _outerController = new _NestedScrollController(this, debugLabel: 'outer');
    _innerController = new _NestedScrollController(this, debugLabel: 'inner');
  }

  ScrollController get outerController => _outerController;
  _NestedScrollController _outerController;

  @protected
  _NestedScrollPosition get _outerPosition {
    if (!_outerController.hasClients)
      return null;
    return _outerController.nestedPositions.single;
  }

  ScrollController get innerController => _innerController;
  _NestedScrollController _innerController;

  @protected
  Iterable<_NestedScrollPosition> get _innerPositions {
    return _innerController.nestedPositions;
  }

  bool get hasScrolledBody {
    for (_NestedScrollPosition position in _innerPositions) {
      if (position.pixels > position.minScrollExtent)
        return true;
    }
    return false;
  }

  ScrollDirection get userScrollDirection => _userScrollDirection;
  ScrollDirection _userScrollDirection = ScrollDirection.idle;

  void updateUserScrollDirection(ScrollDirection value) {
    assert(value != null);
    if (userScrollDirection == value)
      return;
    _userScrollDirection = value;
    _outerPosition.didUpdateScrollDirection(value);
    for (_NestedScrollPosition position in _innerPositions)
      position.didUpdateScrollDirection(value);
  }

  ScrollDragController _currentDrag;

  void beginActivity(ScrollActivity newOuterActivity, _NestedScrollActivityGetter newInnerActivityCallback) {
    _outerPosition.beginActivity(newOuterActivity);
    bool scrolling = newOuterActivity.isScrolling;
    for (_NestedScrollPosition position in _innerPositions) {
      final ScrollActivity newInnerActivity = newInnerActivityCallback(position);
      position.beginActivity(newInnerActivity);
      scrolling = scrolling && newInnerActivity.isScrolling;
    }
    _currentDrag?.dispose();
    _currentDrag = null;
    if (!scrolling)
      updateUserScrollDirection(ScrollDirection.idle);
  }

  @override
  AxisDirection get axisDirection => _outerPosition.axisDirection;

  @override
  void goIdle() {
    beginActivity(
      new IdleScrollActivity(_outerPosition),
      (_NestedScrollPosition position) => new IdleScrollActivity(position),
    );
  }

  @override
  void goBallistic(double velocity) {
    beginActivity(
      _createOuterBallisticScrollActivity(velocity),
      (_NestedScrollPosition position) => _createInnerBallisticScrollActivity(position, velocity),
    );
  }

  ScrollActivity _createOuterBallisticScrollActivity(double velocity) {
    // TODO(ianh): Refactor so this doesn't need to poke at the internals of the
    // other classes here (e.g. calling through _outerPosition.physics)

    // This function creates a ballistic scroll for the outer scrollable.
    //
    // It assumes that the outer scrollable can't be overscrolled, and sets up a
    // ballistic scroll over the combined space of the innerPositions and the
    // outerPosition.

    // First we must pick a representative inner position that we will care
    // about. This is somewhat arbitrary. Ideally we'd pick the one that is "in
    // the center" but there isn't currently a good way to do that so we
    // arbitrarily pick the one that is the furthest away from the infinity we
    // are heading towards.
    _NestedScrollPosition innerPosition;
    if (velocity != 0.0) {
      for (_NestedScrollPosition position in _innerPositions) {
        if (innerPosition != null) {
          if (velocity > 0.0) {
            if (innerPosition.pixels < position.pixels)
              continue;
          } else {
            assert(velocity < 0.0);
            if (innerPosition.pixels > position.pixels)
              continue;
          }
        }
        innerPosition = position;
      }
    }

    if (innerPosition == null) {
      // It's either just us or a velocity=0 situation.
      return _outerPosition._createBallisticScrollActivity(
        _outerPosition.physics.createBallisticSimulation(_outerPosition, velocity),
        mode: _NestedBallisticScrollActivityMode.independent,
      );
    }

    final _NestedScrollMetrics situationReport = _computeSituationReport(innerPosition, velocity);

    return _outerPosition._createBallisticScrollActivity(
      _outerPosition.physics.createBallisticSimulation(situationReport, velocity),
      mode: _NestedBallisticScrollActivityMode.outer,
      minRange: situationReport.minRange,
      maxRange: situationReport.maxRange,
      correctionOffset: situationReport.correctionOffset,
    );
  }

  @protected
  ScrollActivity _createInnerBallisticScrollActivity(_NestedScrollPosition position, double velocity) {
    return position._createBallisticScrollActivity(
      position.physics.createBallisticSimulation(
        velocity == 0 ? position : _computeSituationReport(position, velocity),
        velocity,
      ),
      mode: _NestedBallisticScrollActivityMode.inner,
    );
  }

  _NestedScrollMetrics _computeSituationReport(_NestedScrollPosition innerPosition, double velocity) {
    assert(innerPosition != null);
    double pixels, minRange, maxRange, correctionOffset, extra;
    if (innerPosition.pixels == innerPosition.minScrollExtent) {
      pixels = _outerPosition.pixels.clamp(_outerPosition.minScrollExtent, _outerPosition.maxScrollExtent); // TODO(ianh): gracefully handle out-of-range outer positions
      minRange = _outerPosition.minScrollExtent;
      maxRange = _outerPosition.maxScrollExtent;
      assert(minRange <= maxRange);
      correctionOffset = 0.0;
      extra = 0.0;
    } else {
      assert(innerPosition.pixels != innerPosition.minScrollExtent);
      if (innerPosition.pixels < innerPosition.minScrollExtent) {
        pixels = innerPosition.pixels - innerPosition.minScrollExtent + _outerPosition.minScrollExtent;
      } else {
        assert(innerPosition.pixels > innerPosition.minScrollExtent);
        pixels = innerPosition.pixels - innerPosition.minScrollExtent + _outerPosition.maxScrollExtent;
      }
      if ((velocity > 0.0) && (innerPosition.pixels > innerPosition.minScrollExtent)) {
        // This handles going forward (fling up) and inner list is scrolled past
        // zero. We want to grab the extra pixels immediately to shrink.
        extra = _outerPosition.maxScrollExtent - _outerPosition.pixels;
        assert(extra >= 0.0);
        minRange = pixels;
        maxRange = pixels + extra;
        assert(minRange <= maxRange);
        correctionOffset = _outerPosition.pixels - pixels;
      } else if ((velocity < 0.0) && (innerPosition.pixels < innerPosition.minScrollExtent)) {
        // This handles going backward (fling down) and inner list is
        // underscrolled. We want to grab the extra pixels immediately to grow.
        extra = _outerPosition.pixels - _outerPosition.minScrollExtent;
        assert(extra >= 0.0);
        minRange = pixels - extra;
        maxRange = pixels;
        assert(minRange <= maxRange);
        correctionOffset = _outerPosition.pixels - pixels;
      } else {
        // This handles going forward (fling up) and inner list is
        // underscrolled, OR, going backward (fling down) and inner list is
        // scrolled past zero. We want to skip the pixels we don't need to grow
        // or shrink over.
        if (velocity > 0.0) {
          // shrinking
          extra = _outerPosition.minScrollExtent - _outerPosition.pixels;
        } else {
          assert(velocity < 0.0);
          // growing
          extra = _outerPosition.pixels - (_outerPosition.maxScrollExtent - _outerPosition.minScrollExtent);
        }
        assert(extra <= 0.0);
        minRange = _outerPosition.minScrollExtent;
        maxRange = _outerPosition.maxScrollExtent + extra;
        assert(minRange <= maxRange);
        correctionOffset = 0.0;
      }
    }
    return new _NestedScrollMetrics(
      minScrollExtent: _outerPosition.minScrollExtent,
      maxScrollExtent: _outerPosition.maxScrollExtent + innerPosition.maxScrollExtent - innerPosition.minScrollExtent + extra,
      pixels: pixels,
      viewportDimension: _outerPosition.viewportDimension,
      axisDirection: _outerPosition.axisDirection,
      minRange: minRange,
      maxRange: maxRange,
      correctionOffset: correctionOffset,
    );
  }

  double unnestOffset(double value, _NestedScrollPosition source) {
    if (source == _outerPosition)
      return value.clamp(_outerPosition.minScrollExtent, _outerPosition.maxScrollExtent);
    if (value < source.minScrollExtent)
      return value - source.minScrollExtent + _outerPosition.minScrollExtent;
    return value - source.minScrollExtent + _outerPosition.maxScrollExtent;
  }

  double nestOffset(double value, _NestedScrollPosition target) {
    if (target == _outerPosition)
      return value.clamp(_outerPosition.minScrollExtent, _outerPosition.maxScrollExtent);
    if (value < _outerPosition.minScrollExtent)
      return value - _outerPosition.minScrollExtent + target.minScrollExtent;
    if (value > _outerPosition.maxScrollExtent)
      return value - _outerPosition.maxScrollExtent + target.minScrollExtent;
    return target.minScrollExtent;
  }

  void updateCanDrag() {
    if (!_outerPosition.haveDimensions)
      return;
    double maxInnerExtent = 0.0;
    for (_NestedScrollPosition position in _innerPositions) {
      if (!position.haveDimensions)
        return;
      maxInnerExtent = math.max(maxInnerExtent, position.maxScrollExtent - position.minScrollExtent);
    }
    _outerPosition.updateCanDrag(maxInnerExtent);
  }

  Future<Null> animateTo(double to, {
    @required Duration duration,
    @required Curve curve,
  }) {
    final DrivenScrollActivity outerActivity = _outerPosition.createAnimateScrollActivity(
      nestOffset(to, _outerPosition),
      duration,
      curve,
    );
    final List<Future<Null>> resultFutures = <Future<Null>>[outerActivity.done];
    beginActivity(
      outerActivity,
      (_NestedScrollPosition position) {
        final DrivenScrollActivity innerActivity = position.createAnimateScrollActivity(
          nestOffset(to, position),
          duration,
          curve,
        );
        resultFutures.add(innerActivity.done);
        return innerActivity;
      },
    );
    return Future.wait<Null>(resultFutures);
  }

  void jumpTo(double to) {
    goIdle();
    _outerPosition._localJumpTo(nestOffset(to, _outerPosition));
    for (_NestedScrollPosition position in _innerPositions)
      position._localJumpTo(nestOffset(to, position));
    goBallistic(0.0);
  }

  @override
  double setPixels(double newPixels) {
    assert(false);
    return 0.0;
  }

  void didTouch() {
    _outerPosition._propagateTouched();
    for (_NestedScrollPosition position in _innerPositions)
      position._propagateTouched();
  }

  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) {
    final ScrollDragController drag = new ScrollDragController(
      this,
      details,
      dragCancelCallback,
    );
    beginActivity(
      new DragScrollActivity(_outerPosition, drag),
      (_NestedScrollPosition position) => new DragScrollActivity(position, drag),
    );
    assert(_currentDrag == null);
    _currentDrag = drag;
    return drag;
  }

  @override
  void applyUserOffset(double delta) {
    updateUserScrollDirection(delta > 0.0 ? ScrollDirection.forward : ScrollDirection.reverse);
    assert(delta != 0.0);
    if (_innerPositions.isEmpty) {
      _outerPosition.applyFullDragUpdate(delta);
    } else if (delta < 0.0) {
      // dragging "up"
      // TODO(ianh): prioritize first getting rid of overscroll, and then the
      // outer view, so that the app bar will scroll out of the way asap.
      // Right now we ignore overscroll. This works fine on Android but looks
      // weird on iOS if you fling down then up. The problem is it's not at all
      // clear what this should do when you have multiple inner positions at
      // different levels of overscroll.
      final double innerDelta = _outerPosition.applyClampedDragUpdate(delta);
      if (innerDelta != 0.0) {
        for (_NestedScrollPosition position in _innerPositions)
          position.applyFullDragUpdate(innerDelta);
      }
    } else {
      // dragging "down" - delta is positive
      // prioritize the inner views, so that the inner content will move before the app bar grows
      double outerDelta = 0.0; // it will go positive if it changes
      final List<double> overscrolls = <double>[];
      final List<_NestedScrollPosition> innerPositions = _innerPositions.toList();
      for (_NestedScrollPosition position in innerPositions) {
        final double overscroll = position.applyClampedDragUpdate(delta);
        outerDelta = math.max(outerDelta, overscroll);
        overscrolls.add(overscroll);
      }
      if (outerDelta != 0.0)
        outerDelta -= _outerPosition.applyClampedDragUpdate(outerDelta);
      // now deal with any overscroll
      for (int i = 0; i < innerPositions.length; ++i) {
        final double remainingDelta = overscrolls[i] - outerDelta;
        if (remainingDelta > 0.0)
          innerPositions[i].applyFullDragUpdate(remainingDelta);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    updateParent();
  }

  void updateParent() {
    _outerPosition?.setParent(PrimaryScrollController.of(context));
  }

  @override
  void dispose() {
    _currentDrag?.dispose();
    _currentDrag = null;
    _outerController.dispose();
    _innerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return new CustomScrollView(
      scrollDirection: widget.scrollDirection,
      reverse: widget.reverse,
      physics: new ClampingScrollPhysics(parent: widget.physics),
      controller: _outerController,
      slivers: widget.buildSlivers(context, _innerController, hasScrolledBody),
    );
  }
}

class _NestedScrollMetrics extends FixedScrollMetrics {
  _NestedScrollMetrics({
    @required double minScrollExtent,
    @required double maxScrollExtent,
    @required double pixels,
    @required double viewportDimension,
    @required AxisDirection axisDirection,
    @required this.minRange,
    @required this.maxRange,
    @required this.correctionOffset,
  }) : super(
    minScrollExtent: minScrollExtent,
    maxScrollExtent: maxScrollExtent,
    pixels: pixels,
    viewportDimension: viewportDimension,
    axisDirection: axisDirection,
  );

  final double minRange;

  final double maxRange;

  final double correctionOffset;
}

class _NestedScrollController extends ScrollController {
  _NestedScrollController(this.owner, { this.debugLabel });

  final _NestedScrollViewState owner;

  final String debugLabel;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext state,
    ScrollPosition oldPosition,
  ) {
    return new _NestedScrollPosition(
      owner: owner,
      physics: physics,
      context: state,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }

  @override
  void attach(ScrollPosition position) {
    assert(position is _NestedScrollPosition);
    super.attach(position);
    owner.updateParent();
    owner.updateCanDrag();
  }

  Iterable<_NestedScrollPosition> get nestedPositions sync* {
    yield* positions;
  }

  @override
  void debugFillDescription(List<String> description) {
    super.debugFillDescription(description);
    if (debugLabel != null)
      description.add('debug label: $debugLabel');
  }
}

class _NestedScrollPosition extends ScrollPosition implements ScrollActivityDelegate {
  _NestedScrollPosition({
    @required ScrollPhysics physics,
    @required ScrollContext context,
    ScrollPosition oldPosition,
    @required this.owner,
    this.debugLabel,
  }) : super(physics: physics, context: context, oldPosition: oldPosition) {
    if (pixels == null)
      correctPixels(owner.widget.initialScrollOffset);
    if (activity == null)
      goIdle();
    assert(activity != null);
  }

  final _NestedScrollViewState owner;

  final String debugLabel;

  TickerProvider get vsync => context.vsync;

  ScrollController _parent;

  void setParent(ScrollController value) {
    _parent?.detach(this);
    _parent = value;
    _parent?.attach(this);
  }

  @override
  AxisDirection get axisDirection => context.axisDirection;

  @override
  void absorb(ScrollPosition other) {
    super.absorb(other);
    activity.updateDelegate(this);
  }

  // Returns the amount of delta that was not used.
  double applyClampedDragUpdate(double delta) {
    assert(delta != 0.0);
    final double min = delta < 0.0 ? -double.INFINITY : minScrollExtent;
    final double max = delta > 0.0 ? double.INFINITY : maxScrollExtent;
    final double oldPixels = pixels;
    final double newPixels = (pixels - delta).clamp(min, max);
    final double clampedDelta = newPixels - pixels;
    if (clampedDelta == 0.0)
      return delta;
    final double overscroll = physics.applyBoundaryConditions(this, newPixels);
    final double actualNewPixels = newPixels - overscroll;
    final double offset = actualNewPixels - oldPixels;
    if (offset != 0.0) {
      forcePixels(actualNewPixels);
      didUpdateScrollPositionBy(offset);
    }
    return delta + offset;
  }

  // Returns the overscroll.
  double applyFullDragUpdate(double delta) {
    assert(delta != 0.0);
    final double oldPixels = pixels;
    final double newPixels = pixels - physics.applyPhysicsToUserOffset(this, delta);
    if (oldPixels == newPixels)
      return 0.0; // delta must have been so small we dropped it during floating point addition
    final double overscroll = physics.applyBoundaryConditions(this, newPixels);
    final double actualNewPixels = newPixels - overscroll;
    if (actualNewPixels != oldPixels) {
      forcePixels(actualNewPixels);
      didUpdateScrollPositionBy(actualNewPixels - oldPixels);
    }
    if (overscroll != 0.0) {
      didOverscrollBy(overscroll);
      return overscroll;
    }
    return 0.0;
  }

  @override
  ScrollDirection get userScrollDirection => owner.userScrollDirection;

  DrivenScrollActivity createAnimateScrollActivity(double to, Duration duration, Curve curve) {
    return new DrivenScrollActivity(
      this,
      from: pixels,
      to: to,
      duration: duration,
      curve: curve,
      vsync: vsync,
    );
  }

  @override
  double applyUserOffset(double delta) {
    assert(false);
    return 0.0;
  }

  // This is called by activities when they finish their work.
  @override
  void goIdle() {
    beginActivity(new IdleScrollActivity(this));
  }

  // This is called by activities when they finish their work and want to go ballistic.
  @override
  void goBallistic(double velocity) {
    Simulation simulation;
    if (velocity != 0.0 || outOfRange)
      simulation = physics.createBallisticSimulation(this, velocity);
    beginActivity(_createBallisticScrollActivity(
      simulation,
      mode: _NestedBallisticScrollActivityMode.independent,
    ));
  }

  ScrollActivity _createBallisticScrollActivity(Simulation simulation, {
    @required _NestedBallisticScrollActivityMode mode,
    double minRange,
    double maxRange,
    double correctionOffset,
  }) {
    if (simulation == null)
      return new IdleScrollActivity(this);
    assert(mode != null);
    switch (mode) {
      case _NestedBallisticScrollActivityMode.outer:
        assert(minRange != null);
        assert(maxRange != null);
        assert(correctionOffset != null);
        if (minRange == maxRange)
          return new IdleScrollActivity(this);
        return new _NestedOuterBallisticScrollActivity(owner, this, minRange, maxRange, correctionOffset, simulation, context.vsync);
      case _NestedBallisticScrollActivityMode.inner:
        return new _NestedInnerBallisticScrollActivity(owner, this, simulation, context.vsync);
      case _NestedBallisticScrollActivityMode.independent:
        return new BallisticScrollActivity(this, simulation, context.vsync);
    }
    return null;
  }

  @override
  Future<Null> animateTo(double to, {
    @required Duration duration,
    @required Curve curve,
  }) {
    return owner.animateTo(owner.unnestOffset(to, this), duration: duration, curve: curve);
  }

  @override
  void jumpTo(double value) {
    return owner.jumpTo(owner.unnestOffset(value, this));
  }

  @override
  void jumpToWithoutSettling(double value) {
    assert(false);
  }

  void _localJumpTo(double value) {
    if (pixels != value) {
      final double oldPixels = pixels;
      forcePixels(value);
      didStartScroll();
      didUpdateScrollPositionBy(pixels - oldPixels);
      didEndScroll();
    }
  }

  @override
  void applyNewDimensions() {
    super.applyNewDimensions();
    owner.updateCanDrag();
  }

  void updateCanDrag(double totalExtent) {
    context.setCanDrag(totalExtent > (viewportDimension - maxScrollExtent) || minScrollExtent != maxScrollExtent);
  }

  @override
  void didTouch() {
    owner.didTouch();
  }

  void _propagateTouched() {
    activity.didTouch();
  }

  @override
  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) {
    return owner.drag(details, dragCancelCallback);
  }

  @override
  void dispose() {
    _parent?.detach(this);
    super.dispose();
  }

  @override
  void debugFillDescription(List<String> description) {
    super.debugFillDescription(description);
    if (debugLabel != null)
      description.add('debug label: $debugLabel');
  }
}

enum _NestedBallisticScrollActivityMode { outer, inner, independent }

class _NestedInnerBallisticScrollActivity extends BallisticScrollActivity {
  _NestedInnerBallisticScrollActivity(
    this.owner,
    _NestedScrollPosition position,
    Simulation simulation,
    TickerProvider vsync,
  ) : super(position, simulation, vsync);

  final _NestedScrollViewState owner;

  @override
  _NestedScrollPosition get delegate => super.delegate;

  @override
  void resetActivity() {
    delegate.beginActivity(owner._createInnerBallisticScrollActivity(delegate, velocity));
  }

  @override
  void applyNewDimensions() {
    delegate.beginActivity(owner._createInnerBallisticScrollActivity(delegate, velocity));
  }

  @override
  bool applyMoveTo(double value) {
    return super.applyMoveTo(owner.nestOffset(value, delegate));
  }
}

class _NestedOuterBallisticScrollActivity extends BallisticScrollActivity {
  _NestedOuterBallisticScrollActivity(
    this.owner,
    _NestedScrollPosition position,
    this.minRange,
    this.maxRange,
    this.correctionOffset,
    Simulation simulation,
    TickerProvider vsync,
  ) : super(position, simulation, vsync) {
    assert(minRange != maxRange);
    assert(maxRange > minRange);
  }

  final _NestedScrollViewState owner;

  final double minRange;
  final double maxRange;
  final double correctionOffset;

  @override
  _NestedScrollPosition get delegate => super.delegate;

  @override
  void resetActivity() {
    delegate.beginActivity(owner._createOuterBallisticScrollActivity(velocity));
  }

  @override
  void applyNewDimensions() {
    delegate.beginActivity(owner._createOuterBallisticScrollActivity(velocity));
  }

  @override
  bool applyMoveTo(double value) {
    bool done = false;
    if (velocity > 0.0) {
      if (value < minRange)
        return true;
      if (value > maxRange) {
        value = maxRange;
        done = true;
      }
    } else if (velocity < 0.0) {
      assert(velocity < 0.0);
      if (value > maxRange)
        return true;
      if (value < minRange) {
        value = minRange;
        done = true;
      }
    } else {
      value = value.clamp(minRange, maxRange);
      done = true;
    }
    final bool result = super.applyMoveTo(value + correctionOffset);
    assert(result); // since we tried to pass an in-range value, it shouldn't ever overflow
    return !done;
  }

  @override
  String toString() {
    return '$runtimeType($minRange .. $maxRange; correcting by $correctionOffset)';
  }
}
