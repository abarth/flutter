// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'input_decorator.dart';
import 'text_field.dart';

/// A [FormField] that contains an [Input].
///
/// This is a convenience widget that simply wraps an [Input] widget in a
/// [FormField]. The [FormField] maintains the current value of the [Input] so
/// that you don't need to manage it yourself.
///
/// A [Form] ancestor is not required. The [Form] simply makes it easier to
/// save, reset, or validate multiple fields at once. To use without a [Form],
/// pass a [GlobalKey] to the constructor and use [GlobalKey.currentState] to
/// save or reset the form field.
///
/// To see the use of [TextField], compare these two ways of a implementing
/// a simple two text field form.
///
/// Using [TextField]:
///
/// ```dart
/// String _firstName, _lastName;
/// GlobalKey<FormState> _formKey = new GlobalKey<FormState>();
/// ...
/// new Form(
///   key: _formKey,
///   child: new Row(
///     children: <Widget>[
///       new TextField(
///         labelText: 'First Name',
///         onSaved: (InputValue value) { _firstName = value.text; }
///       ),
///       new TextField(
///         labelText: 'Last Name',
///         onSaved: (InputValue value) { _lastName = value.text; }
///       ),
///       new RaisedButton(
///         child: new Text('SUBMIT'),
///         // Instead of _formKey.currentState, you could wrap the
///         // RaisedButton in a Builder widget to get access to a BuildContext,
///         // and use Form.of(context).
///         onPressed: () { _formKey.currentState.save(); },
///       ),
///    )
///  )
/// ```
///
/// Using [Input] directly:
///
/// ```dart
/// String _firstName, _lastName;
/// InputValue _firstNameValue = const InputValue();
/// InputValue _lastNameValue = const InputValue();
/// ...
/// new Row(
///   children: <Widget>[
///     new Input(
///       value: _firstNameValue,
///       labelText: 'First Name',
///       onChanged: (InputValue value) { setState( () { _firstNameValue = value; } ); }
///     ),
///     new Input(
///       value: _lastNameValue,
///       labelText: 'Last Name',
///       onChanged: (InputValue value) { setState( () { _lastNameValue = value; } ); }
///     ),
///     new RaisedButton(
///       child: new Text('SUBMIT'),
///       onPressed: () {
///         _firstName = _firstNameValue.text;
///         _lastName = _lastNameValue.text;
///       },
///     ),
///  )
/// ```
class TextFormField extends FormField<String> {
  TextFormField({
    Key key,
    TextEditingController controller,
    FocusNode focusNode,
    InputDecoration decoration: const InputDecoration(),
    TextInputType keyboardType: TextInputType.text,
    TextStyle style,
    bool autofocus: false,
    bool obscureText: false,
    int maxLines: 1,
    FormFieldSetter<String> onSaved,
    FormFieldValidator<String> validator,
  }) : super(
    key: key,
    initialValue: controller != null ? controller.value.text : '',
    onSaved: onSaved,
    validator: validator,
    builder: (FormFieldState<String> field) {
      return new TextField(
        controller: controller,
        focusNode: focusNode,
        decoration: decoration,
        keyboardType: keyboardType,
        style: style,
        autofocus: autofocus,
        obscureText: obscureText,
        maxLines: maxLines,
        onChanged: (String value) {
          field.onChanged(value);
        },
      );
    },
  );
}
