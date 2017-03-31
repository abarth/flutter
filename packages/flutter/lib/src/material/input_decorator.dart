// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'colors.dart';
import 'debug.dart';
import 'icon.dart';
import 'icon_theme.dart';
import 'icon_theme_data.dart';
import 'theme.dart';

class InputDecoration {
  const InputDecoration({
    this.icon,
    this.labelText,
    this.labelStyle,
    this.hintText,
    this.hintStyle,
    this.errorText,
    this.errorStyle,
    this.isDense: false,
    this.hideDivider: false,
  });

  /// An icon to show adjacent to the input field.
  ///
  /// The size and color of the icon is configured automatically using an
  /// [IconTheme] and therefore does not need to be explicitly given in the
  /// icon widget.
  ///
  /// See [Icon], [ImageIcon].
  final Widget icon;

  /// Text that appears above the child or over it, if the input is empty is true.
  final String labelText;

  /// The style to use for the label. It's also used for the label when the label
  /// appears over the child.
  final TextStyle labelStyle;

  /// Text that appears over the child if isEmpty is true and labelText is null.
  final String hintText;

  /// The style to use for the hint text.
  final TextStyle hintStyle;

  /// Text that appears below the child. If errorText is non-null the divider
  /// that appears below the child is red.
  final String errorText;

  /// The style to use for the error text.
  final TextStyle errorStyle;

  /// Whether the input container is part of a dense form (i.e., uses less vertical space).
  ///
  /// Defaults to false.
  final bool isDense;

  /// Whether to hide the divider below the child and above the error text.
  ///
  /// Defaults to false.
  final bool hideDivider;
}

/// Displays the visual elements of a material design text field around an
/// arbitrary child widget.
///
/// Use [InputDecorator] to create widgets that look and behave like the [Input]
/// widget.
///
/// Requires one of its ancestors to be a [Material] widget.
///
/// See also:
///
/// * [Input], which combines an [InputDecorator] with an [InputField].
class InputDecorator extends StatefulWidget {
  InputDecorator({
    Key key,
    @required this.decoration,
    this.baseStyle,
    this.isFocused: false,
    this.isEmpty: false,
    this.child,
  }) : super(key: key);

  final InputDecoration decoration;

  final TextStyle baseStyle;

  /// True if the hint and label should be displayed as if the child had the focus.
  ///
  /// Defaults to false.
  final bool isFocused;

  /// Should the hint and label be displayed as if no value had been input
  /// to the child.
  ///
  /// Defaults to false.
  final bool isEmpty;

  /// The widget below this widget in the tree.
  final Widget child;

  @override
  _InputDecoratorState createState() => new _InputDecoratorState();
}

const Duration _kTransitionDuration = const Duration(milliseconds: 200);
const Curve _kTransitionCurve = Curves.fastOutSlowIn;

class _InputDecoratorState extends State<InputDecorator> {
  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasMaterial(context));
    final ThemeData themeData = Theme.of(context);
    final String errorText = config.errorText;

    final TextStyle textStyle = config.style ?? themeData.textTheme.subhead;
    Color activeColor = themeData.hintColor;
    if (config.focused) {
      switch (themeData.brightness) {
        case Brightness.dark:
          activeColor = themeData.accentColor;
          break;
        case Brightness.light:
          activeColor = themeData.primaryColor;
          break;
      }
    }
    double topPadding = config.isDense ? 12.0 : 16.0;

    final List<Widget> stackChildren = <Widget>[];

    // If we're not focused, there's not value, and labelText was provided,
    // then the label appears where the hint would. And we will not show
    // the hintText.
    final bool hasInlineLabel = !config.focused && config.labelText != null && config.isEmpty;

    if (config.labelText != null) {
      final TextStyle labelStyle = hasInlineLabel ?
        textStyle.copyWith(color: themeData.hintColor) :
        themeData.textTheme.caption.copyWith(color: activeColor);

      final double topPaddingIncrement = themeData.textTheme.caption.fontSize + (config.isDense ? 4.0 : 8.0);
      double top = topPadding;
      if (hasInlineLabel)
        top += topPaddingIncrement + textStyle.fontSize - labelStyle.fontSize;

      stackChildren.add(
        new AnimatedPositioned(
          left: 0.0,
          top: top,
          duration: _kTransitionDuration,
          curve: _kTransitionCurve,
          child: new _AnimatedLabel(
            text: config.labelText,
            style: labelStyle,
            duration: _kTransitionDuration,
            curve: _kTransitionCurve,
          )
        ),
      );

      topPadding += topPaddingIncrement;
    }

    if (config.hintText != null) {
      final TextStyle hintStyle = textStyle.copyWith(color: themeData.hintColor);
      stackChildren.add(
        new Positioned(
          left: 0.0,
          top: topPadding + textStyle.fontSize - hintStyle.fontSize,
          child: new AnimatedOpacity(
            opacity: (config.isEmpty && !hasInlineLabel) ? 1.0 : 0.0,
            duration: _kTransitionDuration,
            curve: _kTransitionCurve,
            child: new IgnorePointer(
              child: new Text(config.hintText, style: hintStyle),
            ),
          ),
        ),
      );
    }

    final Color borderColor = errorText == null ? activeColor : themeData.errorColor;
    final double bottomPadding = config.isDense ? 8.0 : 1.0;
    final double bottomBorder = 2.0;
    final double bottomHeight = config.isDense ? 14.0 : 18.0;

    final EdgeInsets padding = new EdgeInsets.only(top: topPadding, bottom: bottomPadding);
    final Border border = new Border(
      bottom: new BorderSide(
        color: borderColor,
        width: bottomBorder,
      )
    );
    final EdgeInsets margin = new EdgeInsets.only(bottom: bottomHeight - (bottomPadding + bottomBorder));

    Widget divider;
    if (!config.showDivider) {
      divider = new Container(
        margin: margin + new EdgeInsets.only(bottom: bottomBorder),
        padding: padding,
        child: config.child,
      );
    } else {
      divider = new AnimatedContainer(
        margin: margin,
        padding: padding,
        duration: _kTransitionDuration,
        curve: _kTransitionCurve,
        decoration: new BoxDecoration(
          border: border,
        ),
        child: config.child,
      );
    }
    stackChildren.add(divider);

    if (!config.isDense) {
      final TextStyle errorStyle = themeData.textTheme.caption.copyWith(color: themeData.errorColor);
      stackChildren.add(new Positioned(
        left: 0.0,
        bottom: 0.0,
        child: new Text(errorText ?? '', style: errorStyle)
      ));
    }

    Widget textField = new Stack(children: stackChildren);

    if (config.icon != null) {
      final double iconSize = config.isDense ? 18.0 : 24.0;
      final double iconTop = topPadding + (textStyle.fontSize - iconSize) / 2.0;
      textField = new Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          new Container(
            margin: new EdgeInsets.only(top: iconTop),
            width: config.isDense ? 40.0 : 48.0,
            child: new IconTheme.merge(
              context: context,
              data: new IconThemeData(
                color: config.focused ? activeColor : Colors.black45,
                size: config.isDense ? 18.0 : 24.0
              ),
              child: config.icon
            )
          ),
          new Expanded(child: textField)
        ]
      );
    }

    return textField;
  }
}

// Helper widget to smoothly animate the labelText of an Input, as it
// transitions between inline and caption.
class _AnimatedLabel extends ImplicitlyAnimatedWidget {
  _AnimatedLabel({
    Key key,
    this.text,
    this.style,
    Curve curve: Curves.linear,
    Duration duration,
  }) : super(key: key, curve: curve, duration: duration) {
    assert(style != null);
  }

  final String text;
  final TextStyle style;

  @override
  _AnimatedLabelState createState() => new _AnimatedLabelState();

  @override
  void debugFillDescription(List<String> description) {
    super.debugFillDescription(description);
    '$style'.split('\n').forEach(description.add);
  }
}

class _AnimatedLabelState extends AnimatedWidgetBaseState<_AnimatedLabel> {
  TextStyleTween _style;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _style = visitor(_style, config.style, (dynamic value) => new TextStyleTween(begin: value));
  }

  @override
  Widget build(BuildContext context) {
    TextStyle style = _style.evaluate(animation);
    double scale = 1.0;
    if (style.fontSize != config.style.fontSize) {
      // While the fontSize is transitioning, use a scaled Transform as a
      // fraction of the original fontSize. That way we get a smooth scaling
      // effect with no snapping between discrete font sizes.
      scale = style.fontSize / config.style.fontSize;
      style = style.copyWith(fontSize: config.style.fontSize);
    }

    return new Transform(
      transform: new Matrix4.identity()..scale(scale),
      child: new Text(
        config.text,
        style: style,
      )
    );
  }
}
