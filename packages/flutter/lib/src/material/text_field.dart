// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'input_decorator.dart';
import 'text_selection.dart';
import 'theme.dart';

export 'package:flutter/services.dart' show TextInputType;

const Duration _kTransitionDuration = const Duration(milliseconds: 200);
const Curve _kTransitionCurve = Curves.fastOutSlowIn;

class TextField extends StatefulWidget {
  TextField({
    Key key,
    this.controller,
    this.focusNode,
    this.decoration: const InputDecoration(),
    this.keyboardType: TextInputType.text,
    this.style,
    this.autofocus: false,
    this.obscureText: false,
    this.maxLines: 1,
    this.onChanged,
    this.onSubmitted,
  }) : super(key: key);

  /// Controls the text being edited.
  /// 
  /// If null, this widget will creates its own [TextEditingController].
  final TextEditingController controller;

  /// Controls whether this widget has keyboard focus.
  /// 
  /// If null, this widget will create its own [FocusNode].
  final FocusNode focusNode;

  /// The decoration to show around the text field.
  /// 
  /// By default, draws a horizontal line under the input field but can be
  /// configured to show an icon, label, hint text, and error text.
  /// 
  /// Set this field to null to hide the decoration entirely.
  final InputDecoration decoration;

  /// The type of keyboard to use for editing the text.
  final TextInputType keyboardType;

  /// The style to use for the text being edited.
  final TextStyle style;

  /// Whether this input field should focus itself if nothing else is already focused.
  /// If true, the keyboard will open as soon as this input obtains focus. Otherwise,
  /// the keyboard is only shown after the user taps the text field.
  ///
  /// Defaults to false.
  // See https://github.com/flutter/flutter/issues/7035 for the rationale for this
  // keyboard behavior.
  final bool autofocus;

  /// Whether to hide the text being edited (e.g., for passwords).
  ///
  /// When this is set to true, all the characters in the input are replaced by
  /// U+2022 BULLET characters (•).
  ///
  /// Defaults to false.
  final bool obscureText;

  /// The maximum number of lines for the text to span, wrapping if necessary.
  /// If this is 1 (the default), the text will not wrap, but will scroll
  /// horizontally instead.
  final int maxLines;

  /// Called when the text being edited changes.
  final ValueChanged<String> onChanged;

  /// Called when the user indicates that they are done editing the text in the field.
  final ValueChanged<String> onSubmitted;

  @override
  _TextFieldState createState() => new _TextFieldState();

  @override
  void debugFillDescription(List<String> description) {
    super.debugFillDescription(description);
    if (controller != null)
      description.add('controller: $controller');
    if (focusNode != null)
      description.add('focusNode: $focusNode');
    description.add('decoration: $decoration');
    if (keyboardType != TextInputType.text)
      description.add('keyboardType: $keyboardType');
    if (style != null)
      description.add('style: $style');
    if (autofocus)
      description.add('autofocus: $autofocus');
    if (obscureText)
      description.add('obscureText: $obscureText');
    if (maxLines != 1)
      description.add('maxLines: $maxLines');
  }
}

class _TextFieldState extends State<TextField> {
  final GlobalKey<EditableTextState> _editableTextKey = new GlobalKey<EditableTextState>();

  TextEditingController _controller;
  TextEditingController get _effectiveController => config.controller ?? _controller;

  FocusNode _focusNode;
  FocusNode get _effectiveFocusNode => config.focusNode ?? (_focusNode ??= new FocusNode());

  @override
  void initState() {
    super.initState();
    if (config.controller == null)
      _controller = new TextEditingController();
  }

  @override
  void didUpdateConfig(TextField oldConfig) {
    if (config.controller == null && oldConfig.controller != null)
      _controller == new TextEditingController.fromValue(oldConfig.controller.value);
    else if (config.controller != null && oldConfig.controller == null)
      _controller = null;
  }

  @override
  void dispose() {
    _focusNode?.dispose();
    super.dispose();
  }

  void _requestKeyboard() {
    _editableTextKey.currentState?.requestKeyboard();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData themeData = Theme.of(context);
    final TextStyle style = config.style ?? themeData.textTheme.subhead;
    final TextEditingController controller = _effectiveController;
    final FocusNode focusNode = _effectiveFocusNode;

    Widget child = new RepaintBoundary(
      child: new EditableText(
        key: _editableTextKey,
        controller: controller,
        focusNode: focusNode,
        keyboardType: config.keyboardType,
        style: style,
        autofocus: config.autofocus,
        obscureText: config.obscureText,
        maxLines: config.maxLines,
        cursorColor: themeData.textSelectionColor,
        selectionColor: themeData.textSelectionColor,
        selectionControls: materialTextSelectionControls,
        onChanged: config.onChanged,
        onSubmitted: config.onSubmitted,
      ),
    );

    if (config.decoration != null) {
      child = new AnimatedBuilder(
        animation: new Listenable.merge(<Listenable>[ focusNode, controller ]),
        builder: (BuildContext context, Widget child) {
          return new InputDecorator(
            decoration: config.decoration,
            baseStyle: config.style,
            isFocused: focusNode.hasFocus,
            isEmpty: controller.value.text.isEmpty,
            child: child,
          );
        },
        child: child,
      );
    }

    return new GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _requestKeyboard,
      child: child,
    );
  }
}
