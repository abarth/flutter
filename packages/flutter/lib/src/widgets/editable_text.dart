// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

import 'basic.dart';
import 'focus_manager.dart';
import 'focus_scope.dart';
import 'framework.dart';
import 'media_query.dart';
import 'scroll_controller.dart';
import 'scroll_physics.dart';
import 'scrollable.dart';
import 'text_selection.dart';

export 'package:flutter/services.dart' show TextEditingValue, TextSelection, TextInputType;

const Duration _kCursorBlinkHalfPeriod = const Duration(milliseconds: 500);

class TextEditingController extends ChangeNotifier {
  TextEditingController({ String text })
    : _value = text == null ? TextEditingValue.empty : new TextEditingValue(text: text);

  TextEditingController.fromValue(TextEditingValue value)
    : _value = value ?? TextEditingValue.empty;

  TextEditingValue get value => _value;
  TextEditingValue _value;
  set value(TextEditingValue newValue) {
    assert(newValue != null);
    if (_value == newValue)
      return;
    _value = newValue;
    notifyListeners();
  }

  String get text => _value.text;
  set text(String newText) {
    value = value.copyWith(text: newText, composing: TextRange.empty);
  }

  TextSelection get selection => _value.selection;
  set selection(TextSelection newSelection) {
    value = value.copyWith(selection: newSelection, composing: TextRange.empty);
  }

  void clear() {
    value = TextEditingValue.empty;
  }

  void clearComposing() {
    value = value.copyWith(composing: TextRange.empty);
  }

  @override
  String toString() {
    return '$runtimeType#$hashCode($value)';
  }
}

/// A basic text input field.
///
/// This widget interacts with the [TextInput] service to let the user edit the
/// text it contains. It also provides scrolling, selection, and cursor
/// movement. This widget does not provide any focus management (e.g.,
/// tap-to-focus).
///
/// Rather than using this widget directly, consider using [InputField], which
/// adds tap-to-focus and cut, copy, and paste commands, or [TextField], which
/// is a full-featured, material-design text input field with placeholder text,
/// labels, and [Form] integration.
///
/// See also:
///
///  * [InputField], which adds tap-to-focus and cut, copy, and paste commands.
///  * [TextField], which is a full-featured, material-design text input field
///    with placeholder text, labels, and [Form] integration.
class EditableText extends StatefulWidget {
  /// Creates a basic text input control.
  ///
  /// The [controller], [focusNode], [style], and [cursorColor] arguments must
  /// not be null.
  EditableText({
    Key key,
    @required this.controller,
    @required this.focusNode,
    this.obscureText: false,
    @required this.style,
    @required this.cursorColor,
    this.textScaleFactor,
    this.maxLines: 1,
    this.autofocus: false,
    this.selectionColor,
    this.selectionControls,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
  }) : super(key: key) {
    assert(controller != null);
    assert(focusNode != null);
    assert(obscureText != null);
    assert(style != null);
    assert(cursorColor != null);
    assert(maxLines != null);
    assert(autofocus != null);
  }

  /// Controls the text being edited.
  final TextEditingController controller;

  /// Controls whether this widget has keyboard focus.
  final FocusNode focusNode;

  /// Whether to hide the text being edited (e.g., for passwords).
  ///
  /// Defaults to false.
  final bool obscureText;

  /// The text style to use for the editable text.
  final TextStyle style;

  /// The number of font pixels for each logical pixel.
  ///
  /// For example, if the text scale factor is 1.5, text will be 50% larger than
  /// the specified font size.
  ///
  /// Defaults to [MediaQuery.textScaleFactor].
  final double textScaleFactor;

  /// The color to use when painting the cursor.
  final Color cursorColor;

  /// The maximum number of lines for the text to span, wrapping if necessary.
  /// If this is 1 (the default), the text will not wrap, but will scroll
  /// horizontally instead.
  final int maxLines;

  /// Whether this input field should focus itself if nothing else is already focused.
  /// If true, the keyboard will open as soon as this input obtains focus. Otherwise,
  /// the keyboard is only shown after the user taps the text field.
  ///
  /// Defaults to false.
  final bool autofocus;

  /// The color to use when painting the selection.
  final Color selectionColor;

  /// Optional delegate for building the text selection handles and toolbar.
  final TextSelectionControls selectionControls;

  /// The type of keyboard to use for editing the text.
  final TextInputType keyboardType;

  /// Called when the text being edited changes.
  final ValueChanged<String> onChanged;

  /// Called when the user indicates that they are done editing the text in the field.
  final ValueChanged<String> onSubmitted;

  @override
  EditableTextState createState() => new EditableTextState();
}

/// State for a [EditableText].
class EditableTextState extends State<EditableText> implements TextInputClient {
  Timer _cursorTimer;
  bool _showCursor = false;

  TextInputConnection _textInputConnection;
  TextSelectionOverlay _selectionOverlay;

  final ScrollController _scrollController = new ScrollController();
  bool _didAutoFocus = false;

  // State lifecycle:

  @override
  void initState() {
    super.initState();
    config.controller.addListener(_didChangeTextEditingValue);
    config.focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didAutoFocus && config.autofocus) {
      _didRequestKeyboard = true;
      FocusScope.of(context).autofocus(config.focusNode);
      _didAutoFocus = true;
    }
  }

  @override
  void didUpdateConfig(EditableText oldConfig) {
    if (config.controller != oldConfig.controller) {
      oldConfig.controller.removeListener(_didChangeTextEditingValue);
      config.controller.addListener(_didChangeTextEditingValue);
      if (_isAttachedToKeyboard && config.controller.value != oldConfig.controller.value)
        _textInputConnection.setEditingState(config.controller.value);
     }
    if (config.focusNode != oldConfig.focusNode) {
      oldConfig.focusNode.removeListener(_handleFocusChanged);
      config.focusNode.addListener(_handleFocusChanged);
    }
  }

  @override
  void dispose() {
    config.controller.removeListener(_didChangeTextEditingValue);
    if (_isAttachedToKeyboard) {
      _textInputConnection.close();
      _textInputConnection = null;
    }
    assert(!_isAttachedToKeyboard);
    if (_cursorTimer != null)
      _stopCursorTimer();
    assert(_cursorTimer == null);
    _selectionOverlay?.dispose();
    _selectionOverlay = null;
    config.focusNode.removeListener(_handleFocusChanged);
    super.dispose();
  }

  // TextInputClient implementation:

  @override
  void updateEditingValue(TextEditingValue value) {
    if (value.text != _value.text)
      _hideSelectionOverlayIfNeeded();
    _value = value;
    if (config.onChanged != null)
      config.onChanged(value.text);
  }

  @override
  void performAction(TextInputAction action) {
    config.controller.clearComposing();
    config.focusNode.unfocus();
    if (config.onSubmitted != null)
      config.onSubmitted(_value.text);
  }

  TextEditingValue get _value => config.controller.value;
  set _value(TextEditingValue value) {
    config.controller.value = value;
  }

  void _didChangeTextEditingValue() {
    setState(() { /* We use config.controller.value in build(). */ });
  }

  bool get _isAttachedToKeyboard => _textInputConnection != null && _textInputConnection.attached;

  bool get _isMultiline => config.maxLines > 1;

  // Calculate the new scroll offset so the cursor remains visible.
  double _getScrollOffsetForCaret(Rect caretRect) {
    final double caretStart = _isMultiline ? caretRect.top : caretRect.left;
    final double caretEnd = _isMultiline ? caretRect.bottom : caretRect.right;
    double scrollOffset = _scrollController.offset;
    final double viewportExtent = _scrollController.position.viewportDimension;
    if (caretStart < 0.0)  // cursor before start of bounds
      scrollOffset += caretStart;
    else if (caretEnd >= viewportExtent)  // cursor after end of bounds
      scrollOffset += caretEnd - viewportExtent;
    return scrollOffset;
  }

  bool _didRequestKeyboard = false;

  void _attachOrDetachKeyboard(bool focused) {
    if (focused && !_isAttachedToKeyboard && _didRequestKeyboard) {
      _textInputConnection = TextInput.attach(this, new TextInputConfiguration(inputType: config.keyboardType))
        ..setEditingState(_value)
        ..show();
    } else if (!focused) {
      if (_isAttachedToKeyboard) {
        _textInputConnection.close();
        _textInputConnection = null;
      }
      config.controller.clearComposing();
    }
    _didRequestKeyboard = false;
  }

  /// Express interest in interacting with the keyboard.
  ///
  /// If this control is already attached to the keyboard, this function will
  /// request that the keyboard become visible. Otherwise, this function will
  /// ask the focus system that it become focused. If successful in acquiring
  /// focus, the control will then attach to the keyboard and request that the
  /// keyboard become visible.
  void requestKeyboard() {
    if (_isAttachedToKeyboard) {
      _textInputConnection.show();
    } else {
      _didRequestKeyboard = true;
      if (config.focusNode.hasFocus)
        _attachOrDetachKeyboard(true);
      else
        FocusScope.of(context).requestFocus(config.focusNode);
    }
  }

  void _hideSelectionOverlayIfNeeded() {
    _selectionOverlay?.hide();
    _selectionOverlay = null;
  }

  void _handleSelectionChanged(TextSelection selection, RenderEditable renderObject, bool longPress) {
    // Note that this will show the keyboard for all selection changes on the
    // EditableWidget, not just changes triggered by user gestures.
    requestKeyboard();

    _hideSelectionOverlayIfNeeded();
    config.controller.selection = selection;

    if (config.selectionControls != null) {
      _selectionOverlay = new TextSelectionOverlay(
        context: context,
        value: _value,
        debugRequiredFor: config,
        renderObject: renderObject,
        onSelectionOverlayChanged: _handleSelectionOverlayChanged,
        selectionControls: config.selectionControls,
      );
      if (_value.text.isNotEmpty || longPress)
        _selectionOverlay.showHandles();
      if (longPress)
        _selectionOverlay.showToolbar();
    }
  }

  void _handleSelectionOverlayChanged(TextEditingValue value, Rect caretRect) {
    assert(!value.composing.isValid);  // composing range must be empty while selecting.
    _value = value;
    _scrollController.jumpTo(_getScrollOffsetForCaret(caretRect));
  }

  /// Whether the blinking cursor is actually visible at this precise moment
  /// (it's hidden half the time, since it blinks).
  @visibleForTesting
  bool get cursorCurrentlyVisible => _showCursor;

  /// The cursor blink interval (the amount of time the cursor is in the "on"
  /// state or the "off" state). A complete cursor blink period is twice this
  /// value (half on, half off).
  @visibleForTesting
  Duration get cursorBlinkInterval => _kCursorBlinkHalfPeriod;

  void _cursorTick(Timer timer) {
    setState(() {
      _showCursor = !_showCursor;
    });
  }

  void _startCursorTimer() {
    _showCursor = true;
    _cursorTimer = new Timer.periodic(_kCursorBlinkHalfPeriod, _cursorTick);
  }

  void _handleFocusChanged() {
    final bool focused = config.focusNode.hasFocus;
    _attachOrDetachKeyboard(focused);

    if (_cursorTimer == null && focused && _value.selection.isCollapsed)
      _startCursorTimer();
    else if (_cursorTimer != null && (!focused || !_value.selection.isCollapsed))
      _stopCursorTimer();

    if (_selectionOverlay != null) {
      if (focused) {
        _selectionOverlay.update(_value);
      } else {
        _selectionOverlay.dispose();
        _selectionOverlay = null;
      }
    }
  }

  void _stopCursorTimer() {
    _cursorTimer.cancel();
    _cursorTimer = null;
    _showCursor = false;
  }

  @override
  Widget build(BuildContext context) {
    FocusScope.of(context).reparentIfNeeded(config.focusNode);
    return new Scrollable(
      axisDirection: _isMultiline ? AxisDirection.down : AxisDirection.right,
      controller: _scrollController,
      physics: const ClampingScrollPhysics(),
      viewportBuilder: (BuildContext context, ViewportOffset offset) {
        return new _Editable(
          value: _value,
          style: config.style,
          cursorColor: config.cursorColor,
          showCursor: _showCursor,
          maxLines: config.maxLines,
          selectionColor: config.selectionColor,
          textScaleFactor: config.textScaleFactor ?? MediaQuery.of(context).textScaleFactor,
          obscureText: config.obscureText,
          offset: offset,
          onSelectionChanged: _handleSelectionChanged,
        );
      },
    );
  }
}

class _Editable extends LeafRenderObjectWidget {
  _Editable({
    Key key,
    this.value,
    this.style,
    this.cursorColor,
    this.showCursor,
    this.maxLines,
    this.selectionColor,
    this.textScaleFactor,
    this.obscureText,
    this.offset,
    this.onSelectionChanged,
  }) : super(key: key);

  final TextEditingValue value;
  final TextStyle style;
  final Color cursorColor;
  final bool showCursor;
  final int maxLines;
  final Color selectionColor;
  final double textScaleFactor;
  final bool obscureText;
  final ViewportOffset offset;
  final SelectionChangedHandler onSelectionChanged;

  @override
  RenderEditable createRenderObject(BuildContext context) {
    return new RenderEditable(
      text: _styledTextSpan,
      cursorColor: cursorColor,
      showCursor: showCursor,
      maxLines: maxLines,
      selectionColor: selectionColor,
      textScaleFactor: textScaleFactor,
      selection: value.selection,
      offset: offset,
      onSelectionChanged: onSelectionChanged,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderEditable renderObject) {
    renderObject
      ..text = _styledTextSpan
      ..cursorColor = cursorColor
      ..showCursor = showCursor
      ..maxLines = maxLines
      ..selectionColor = selectionColor
      ..textScaleFactor = textScaleFactor
      ..selection = value.selection
      ..offset = offset
      ..onSelectionChanged = onSelectionChanged;
  }

  TextSpan get _styledTextSpan {
    if (!obscureText && value.composing.isValid) {
      final TextStyle composingStyle = style.merge(
        const TextStyle(decoration: TextDecoration.underline)
      );

      return new TextSpan(
        style: style,
        children: <TextSpan>[
          new TextSpan(text: value.composing.textBefore(value.text)),
          new TextSpan(
            style: composingStyle,
            text: value.composing.textInside(value.text)
          ),
          new TextSpan(text: value.composing.textAfter(value.text))
      ]);
    }

    String text = value.text;
    if (obscureText)
      text = new String.fromCharCodes(new List<int>.filled(text.length, 0x2022));
    return new TextSpan(style: style, text: text);
  }
}
