// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'basic.dart';
import 'focus.dart';
import 'framework.dart';
import 'media_query.dart';
import 'scroll_controller.dart';
import 'scroll_physics.dart';
import 'scrollable.dart';
import 'text_selection.dart';

export 'package:flutter/services.dart' show TextSelection, TextInputType;

const Duration _kCursorBlinkHalfPeriod = const Duration(milliseconds: 500);

class TextEditingController extends ChangeNotifier {
  TextEditingController({ String text })
    : _value = text == null ? TextEditingValue.empty : new TextEditingValue(text: text);

  TextEditingController.fromValue(TextEditingValue value)
    : _value = value ?? TextEditingValue.empty;

  TextEditingValue get value => _value;
  TextEditingValue _value;
  set value(TextEditingValue newValue) {
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
  EditableText({
    Key key,
    this.controller,
    @required this.focusKey,
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
    assert(focusKey != null);
    assert(obscureText != null);
    assert(style != null);
    assert(cursorColor != null);
    assert(maxLines != null);
    assert(autofocus != null);
  }

  final TextEditingController controller;

  /// Key of the enclosing widget that holds the focus.
  final GlobalKey focusKey;

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

  TextEditingController _controller;
  final ScrollController _scrollController = new ScrollController();

  // State lifecycle:

  @override
  void initState() {
    super.initState();
    _controller = config.controller ?? new TextEditingController();
    _controller.addListener(_didChangeTextEditingValue);
  }

  @override
  void didUpdateConfig(EditableText oldConfig) {
    if (config.controller != oldConfig.controller) {
      _controller.removeListener(_didChangeTextEditingValue);
      _controller = config.controller ?? new TextEditingController();
      _controller.addListener(_didChangeTextEditingValue);
      if (_isAttachedToKeyboard)
        _textInputConnection.setEditingState(_controller.value);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_didChangeTextEditingValue);
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
    super.dispose();
  }

  // TextInputClient implementation:

  @override
  void updateEditingValue(TextEditingValue value) {
    if (value.text != _controller.value.text)
      _hideSelectionOverlayIfNeeded();
    _controller.value = value;
    if (config.onChanged != null)
      config.onChanged(value.text);
  }

  @override
  void performAction(TextInputAction action) {
    _controller.clearComposing();
    Focus.clear(context);
    if (config.onSubmitted != null)
      config.onSubmitted(_controller.value.text);
  }

  void _didChangeTextEditingValue() {
    setState(() { /* We use _controller.value in build(). */ });
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

  // True if the focus was explicitly requested last frame. This ensures we
  // don't show the keyboard when focus defaults back to the EditableText.
  bool _requestingFocus = false;

  void _attachOrDetachKeyboard(bool focused) {
    if (focused && !_isAttachedToKeyboard && (_requestingFocus || config.autofocus)) {
      _textInputConnection = TextInput.attach(this, new TextInputConfiguration(inputType: config.keyboardType))
        ..setEditingState(_controller.value)
        ..show();
    } else if (!focused) {
      if (_isAttachedToKeyboard) {
        _textInputConnection.close();
        _textInputConnection = null;
      }
      _controller.clearComposing();
    }
    _requestingFocus = false;
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
      Focus.moveTo(config.focusKey);
      setState(() {
        _requestingFocus = true;
      });
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
    _controller.selection = selection;

    if (config.selectionControls != null) {
      _selectionOverlay = new TextSelectionOverlay(
        context: context,
        value: _controller.value,
        debugRequiredFor: config,
        renderObject: renderObject,
        onSelectionOverlayChanged: _handleSelectionOverlayChanged,
        selectionControls: config.selectionControls,
      );
      if (_controller.value.text.isNotEmpty || longPress)
        _selectionOverlay.showHandles();
      if (longPress)
        _selectionOverlay.showToolbar();
    }
  }

  void _handleSelectionOverlayChanged(TextEditingValue value, Rect caretRect) {
    assert(!value.composing.isValid);  // composing range must be empty while selecting
    _controller.value = value;
    _scrollController.jumpTo(_getScrollOffsetForCaret(caretRect));
  }

  /// Whether the blinking cursor is actually visible at this precise moment
  /// (it's hidden half the time, since it blinks).
  bool get cursorCurrentlyVisible => _showCursor;

  /// The cursor blink interval (the amount of time the cursor is in the "on"
  /// state or the "off" state). A complete cursor blink period is twice this
  /// value (half on, half off).
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

  void _stopCursorTimer() {
    _cursorTimer.cancel();
    _cursorTimer = null;
    _showCursor = false;
  }

  @override
  Widget build(BuildContext context) {
    final bool focused = Focus.at(config.focusKey.currentContext);
    _attachOrDetachKeyboard(focused);

    if (_cursorTimer == null && focused && _controller.value.selection.isCollapsed)
      _startCursorTimer();
    else if (_cursorTimer != null && (!focused || !_controller.value.selection.isCollapsed))
      _stopCursorTimer();

    if (_selectionOverlay != null) {
      if (focused) {
        _selectionOverlay.update(_controller.value);
      } else {
        _selectionOverlay.dispose();
        _selectionOverlay = null;
      }
    }

    return new Scrollable(
      axisDirection: _isMultiline ? AxisDirection.down : AxisDirection.right,
      controller: _scrollController,
      physics: const ClampingScrollPhysics(),
      viewportBuilder: (BuildContext context, ViewportOffset offset) {
        return new _Editable(
          value: _controller.value,
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
